# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'base64'
require 'new_relic/agent/obfuscator'
require 'new_relic/agent/transaction_timings'

module NewRelic
  module Agent
    class JavascriptInstrumentor
      include NewRelic::Coerce

      RUM_KEY_LENGTH = 13

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

      def obfuscator
        @obfuscator ||= NewRelic::Agent::Obfuscator.new(NewRelic::Agent.config[:license_key], RUM_KEY_LENGTH)
      end

      def js_enabled_and_ready?
        if !enabled?
          ::NewRelic::Agent.logger.log_once(:debug, :js_agent_disabled,
                                            "JS agent instrumentation is disabled.")
          false
        elsif missing_config?(:js_agent_loader)
          ::NewRelic::Agent.logger.log_once(:debug, :missing_js_agent_loader,
                                            "Missing :js_agent_loader. Skipping browser instrumentation.")
          false
        elsif missing_config?(:beacon)
          ::NewRelic::Agent.logger.log_once(:debug, :missing_beacon,
                                            "Beacon configuration not received (yet?). Skipping browser instrumentation.")
          false
        elsif missing_config?(:browser_key)
          ::NewRelic::Agent.logger.log_once(:debug, :missing_browser_key,
                                            "Browser key is not set. Skipping browser instrumentation.")
          false
        else
          true
        end
      rescue => e
        ::NewRelic::Agent.logger.debug "Failure during 'js_enabled_and_ready?'", e
        false
      end

      def insert_js?(state)
        if !state.current_transaction
          ::NewRelic::Agent.logger.debug "Not in transaction. Skipping browser instrumentation."
          false
        elsif !state.is_transaction_traced?
          ::NewRelic::Agent.logger.debug "Transaction is not traced. Skipping browser instrumentation."
          false
        elsif !state.is_execution_traced?
          ::NewRelic::Agent.logger.debug "Execution is not traced. Skipping browser instrumentation."
          false
        elsif state.current_transaction.ignore_enduser?
          ::NewRelic::Agent.logger.debug "Ignore end user for this transaction is set. Skipping browser instrumentation."
          false
        else
          true
        end
      rescue => e
        ::NewRelic::Agent.logger.debug "Failure during insert_js", e
        false
      end

      def missing_config?(key)
        value = NewRelic::Agent.config[key]
        value.nil? || value.empty?
      end

      def browser_timing_header #THREAD_LOCAL_ACCESS
        return '' unless js_enabled_and_ready? # fast exit

        state = NewRelic::Agent::TransactionState.tl_get

        return '' unless insert_js?(state) # slower exit

        bt_config = browser_timing_config(state)
        return '' if bt_config.empty?

        bt_config + browser_timing_loader
      rescue => e
        ::NewRelic::Agent.logger.debug "Failure during RUM browser_timing_header construction", e
        ''
      end

      def browser_timing_loader
        html_safe_if_needed("\n<script type=\"text/javascript\">#{Agent.config[:js_agent_loader]}</script>")
      end

      def browser_timing_config(state)
        txn = state.current_transaction
        return '' if txn.nil?

        txn.freeze_name_and_execute_if_not_ignored do
          data = data_for_js_agent(state)
          json = NewRelic::JSONWrapper.dump(data)
          return html_safe_if_needed("\n<script type=\"text/javascript\">window.NREUM||(NREUM={});NREUM.info=#{json}</script>")
        end

        ''
      end

      BEACON_KEY           = "beacon".freeze
      ERROR_BEACON_KEY     = "errorBeacon".freeze
      LICENSE_KEY_KEY      = "licenseKey".freeze
      APPLICATIONID_KEY    = "applicationID".freeze
      TRANSACTION_NAME_KEY = "transactionName".freeze
      QUEUE_TIME_KEY       = "queueTime".freeze
      APPLICATION_TIME_KEY = "applicationTime".freeze
      AGENT_KEY            = "agent".freeze
      SSL_FOR_HTTP_KEY     = "sslForHttp".freeze
      ATTS_KEY             = "atts".freeze
      ATTS_USER_SUBKEY     = "u".freeze
      ATTS_AGENT_SUBKEY    = "a".freeze

      # NOTE: Internal prototyping may override this, so leave name stable!
      def data_for_js_agent(state)
        timings = state.timings

        data = {
          BEACON_KEY           => NewRelic::Agent.config[:beacon],
          ERROR_BEACON_KEY     => NewRelic::Agent.config[:error_beacon],
          LICENSE_KEY_KEY      => NewRelic::Agent.config[:browser_key],
          APPLICATIONID_KEY    => NewRelic::Agent.config[:application_id],
          TRANSACTION_NAME_KEY => obfuscator.obfuscate(timings.transaction_name_or_unknown),
          QUEUE_TIME_KEY       => timings.queue_time_in_millis,
          APPLICATION_TIME_KEY => timings.app_time_in_millis,
          AGENT_KEY            => NewRelic::Agent.config[:js_agent_file]
        }

        add_ssl_for_http(data)
        add_attributes(data, state.current_transaction)

        data
      end

      def add_ssl_for_http(data)
        ssl_for_http = NewRelic::Agent.config[:'browser_monitoring.ssl_for_http']
        unless ssl_for_http.nil?
          data[SSL_FOR_HTTP_KEY] = ssl_for_http
        end
      end

      def add_attributes(data, txn)
        return unless txn

        atts = {}
        append_custom_attributes!(txn, atts)
        append_agent_attributes!(txn, atts)

        unless atts.empty?
          json = NewRelic::JSONWrapper.dump(atts)
          data[ATTS_KEY] = obfuscator.obfuscate(json)
        end
      end

      def append_custom_attributes!(txn, atts)
        custom_attributes = txn.attributes.custom_attributes_for(NewRelic::Agent::AttributeFilter::DST_BROWSER_MONITORING)
        unless custom_attributes.empty?
          atts[ATTS_USER_SUBKEY] = custom_attributes
        end
      end

      def append_agent_attributes!(txn, atts)
        agent_attributes = txn.attributes.agent_attributes_for(NewRelic::Agent::AttributeFilter::DST_BROWSER_MONITORING)
        unless agent_attributes.empty?
          atts[ATTS_AGENT_SUBKEY] = agent_attributes
        end
      end

      def html_safe_if_needed(string)
        string = string.html_safe if string.respond_to?(:html_safe)
        string
      end
    end
  end
end
