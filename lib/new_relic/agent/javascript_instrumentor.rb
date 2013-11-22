# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'base64'
require 'new_relic/agent/transaction_timings'

module NewRelic
  module Agent
    class JavascriptInstrumentor
      include NewRelic::Coerce

      def initialize(event_listener)
        event_listener.subscribe(:finished_configuring, &method(:log_configuration))
      end

      def log_configuration
        NewRelic::Agent.logger.debug("JS agent loader requested: #{NewRelic::Agent.config[:'browser_monitoring.loader']}",
                                     "JS agent loader debug: #{NewRelic::Agent.config[:'browser_monitoring.debug']}",
                                     "JS agent loader version: #{NewRelic::Agent.config[:'browser_monitoring.loader_version']}")

        if !NewRelic::Agent.config[:'rum.enabled']
          NewRelic::Agent.logger.debug("Real User Monitoring is disabled for this agent. Edit your configuration to change this.")
        end
      end

      def enabled?
        Agent.config[:'rum.enabled'] && !!Agent.config[:beacon]
      end

      # Memoize license key bytes for obscuring transaction names in javascript
      def license_bytes
        if @license_bytes.nil?
          @license_bytes = []
          NewRelic::Agent.config[:license_key].each_byte {|byte| @license_bytes << byte}
        end
        @license_bytes
      end

      # Obfuscation

      def obfuscate(text)
        obfuscated = ""
        if defined?(::Encoding::ASCII_8BIT)
          obfuscated.force_encoding(::Encoding::ASCII_8BIT)
        end

        index = 0
        text.each_byte{|byte|
          obfuscated.concat((byte ^ license_bytes[index % 13].to_i))
          index+=1
        }

        [obfuscated].pack("m0").gsub("\n", '')
      end

      # Transaction Access

      def current_transaction
        NewRelic::Agent::TransactionState.get.transaction
      end

      def current_timings
        NewRelic::Agent::TransactionState.get.timings
      end

      def browser_monitoring_transaction_name
        current_timings.transaction_name || ::NewRelic::Agent::UNKNOWN_METRIC
      end

      def tt_guid
        state = NewRelic::Agent::TransactionState.get
        return state.request_guid if include_guid?(state)
        ""
      end

      # TODO: Feature envy? Move to TransactionState?
      def include_guid?(state)
        state.request_token &&
          state.timings.app_time_in_seconds > state.transaction.apdex_t
      end

      def tt_token
        return NewRelic::Agent::TransactionState.get.request_token
      end

      # Javascript

      # Should JS agent script be generated? Log if not.
      def insert_js?
        if missing_config?(:js_agent_loader)
          ::NewRelic::Agent.logger.debug "Missing :js_agent_loader. Skipping browser instrumentation."
          false
        elsif missing_config?(:beacon)
          ::NewRelic::Agent.logger.debug "Beacon configuration not received (yet?). Skipping browser instrumentation."
          false
        elsif !enabled?
          ::NewRelic::Agent.logger.debug "JS agent instrumentation is disabled."
          false
        elsif missing_config?(:browser_key)
          ::NewRelic::Agent.logger.debug "Browser key is not set. Skipping browser instrumentation."
          false
        elsif !::NewRelic::Agent.is_transaction_traced?
          ::NewRelic::Agent.logger.debug "Transaction is not traced. Skipping browser instrumentation."
          false
        elsif !::NewRelic::Agent.is_execution_traced?
          ::NewRelic::Agent.logger.debug "Execution is not traced. Skipping browser instrumentation."
          false
        elsif ::NewRelic::Agent::TransactionState.get.request_ignore_enduser
          ::NewRelic::Agent.logger.debug "Ignore end user for this transaction is set. Skipping browser instrumentation."
          false
        else
          true
        end
      end

      def missing_config?(key)
        value = NewRelic::Agent.config[key]
        value.nil? || value.empty?
      end

      def browser_timing_header
        return "" unless insert_js?
        header_js_string
      end

      def browser_timing_config
        return "" unless insert_js?
        NewRelic::Agent::Transaction.freeze_name

        return "" unless current_transaction
        footer_js_string
      end

      # NOTE: Internal prototyping often overrides this, so leave name stable!
      def header_js_string
        html_safe_if_needed("\n<script type=\"text/javascript\">#{Agent.config[:js_agent_loader]}</script>")
      end

      # NOTE: Internal prototyping often overrides this, so leave name stable!
      def footer_js_string
        data = data_for_js_agent
        json = NewRelic.json_dump(data)
        html_safe_if_needed("\n<script type=\"text/javascript\">window.NREUM||(NREUM={});NREUM.info=#{json}</script>")
      end

      BEACON_KEY           = "beacon".freeze
      ERROR_BEACON_KEY     = "errorBeacon".freeze
      LICENSE_KEY_KEY      = "licenseKey".freeze
      APPLICATIONID_KEY    = "applicationID".freeze
      TRANSACTION_NAME_KEY = "transactionName".freeze
      QUEUE_TIME_KEY       = "queueTime".freeze
      APPLICATION_TIME_KEY = "applicationTime".freeze
      TT_GUID_KEY          = "ttGuid".freeze
      AGENT_TOKEN_KEY      = "agentToken".freeze
      AGENT_KEY            = "agent".freeze
      EXTRA_KEY            = "extra".freeze
      SSL_FOR_HTTP_KEY     = "sslForHttp".freeze

      # NOTE: Internal prototyping may override this, so leave name stable!
      def data_for_js_agent
        data = {
          BEACON_KEY           => NewRelic::Agent.config[:beacon],
          ERROR_BEACON_KEY     => NewRelic::Agent.config[:error_beacon],
          LICENSE_KEY_KEY      => NewRelic::Agent.config[:browser_key],
          APPLICATIONID_KEY    => NewRelic::Agent.config[:application_id],
          TRANSACTION_NAME_KEY => obfuscate(browser_monitoring_transaction_name),
          QUEUE_TIME_KEY       => current_timings.queue_time_in_millis,
          APPLICATION_TIME_KEY => current_timings.app_time_in_millis,
          TT_GUID_KEY          => tt_guid,
          AGENT_TOKEN_KEY      => tt_token,
          AGENT_KEY            => NewRelic::Agent.config[:js_agent_file],
          EXTRA_KEY            => obfuscate(formatted_extra_parameter_for_js_agent)
        }
        add_ssl_for_http(data)

        data
      end

      def add_ssl_for_http(data)
        ssl_for_http = NewRelic::Agent.config[:'browser_monitoring.ssl_for_http']
        unless ssl_for_http.nil?
          data[SSL_FOR_HTTP_KEY] = ssl_for_http
        end
      end

      # NOTE: Internal prototyping may override this, so leave name stable!
      def data_for_js_agent_extra_parameter
        return {} unless include_custom_parameters_in_extra?
        current_transaction.custom_parameters.dup
      end

      def include_custom_parameters_in_extra?
        current_transaction &&
          NewRelic::Agent.config[:'analytics_events.enabled'] &&
          NewRelic::Agent.config[:'analytics_events.transactions.enabled'] &&
          NewRelic::Agent.config[:'capture_attributes.page_view_events']
      end

      def formatted_extra_parameter_for_js_agent
        format_extra_data(data_for_js_agent_extra_parameter)
      end

      # Format the props using semicolon separated pairs separated by '=':
      #   product=pro;user=bill@microsoft.com
      def format_extra_data(extra_props)
        event_params(extra_props).
          map {|k,v| format_pair(k, v)}.
          join(';')
      end

      def format_pair(key, value)
        key = escape_special_characters(key)
        value = format_value(value)
        "#{key}=#{value}"
      end

      def escape_special_characters(string)
        string.to_s.tr("\";=", "':-" )
      end

      def format_value(v)
        v = "##{v}" if v.is_a?(Numeric)
        escape_special_characters(v)
      end

      def html_safe_if_needed(string)
        string = string.html_safe if string.respond_to?(:html_safe)
        string
      end
    end
  end
end
