# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'base64'
require 'new_relic/agent/beacon_configuration'
require 'new_relic/agent/transaction_timings'

module NewRelic
  module Agent
    # This module contains support for Real User Monitoring - the
    # javascript generation and configuration
    #
    # @api public
    module BrowserMonitoring
      class DummyTransaction

        attr_accessor :start_time

        def initialize
          @attributes = {}
        end

        def user_attributes
          @attributes
        end

        def queue_time
          0.0
        end

        def timings
          NewRelic::Agent::TransactionTimings.new(0.0, NewRelic::Agent::TransactionState.get)
        end

        def name
          ::NewRelic::Agent::UNKNOWN_METRIC
        end
      end

      @@dummy_txn = DummyTransaction.new

      # This method returns a string suitable for inclusion in a page
      # - known as 'manual instrumentation' for Real User
      # Monitoring. Can return either a script tag with associated
      # javascript, or in the case of disabled Real User Monitoring,
      # an empty string
      #
      # This is the header string - it should be placed as high in the
      # page as is reasonably possible - that is, before any style or
      # javascript inclusions, but after any header-related meta tags
      #
      # @api public
      #
      def browser_timing_header
        insert_js? ? header_js_string : ""
      end

      # This method returns a string suitable for inclusion in a page
      # - known as 'manual instrumentation' for Real User
      # Monitoring. Can return either a script tag with associated
      # javascript, or in the case of disabled Real User Monitoring,
      # an empty string
      #
      # This is the footer string - it should be placed as low in the
      # page as is reasonably possible.
      #
      # @api public
      #
      def browser_timing_footer
        if insert_js?
          NewRelic::Agent::Transaction.freeze_name
          generate_footer_js(NewRelic::Agent.instance.beacon_configuration)
        else
          ""
        end
      end

      module_function

      def obfuscate(config, text)
        obfuscated = ""
        if defined?(::Encoding::ASCII_8BIT)
          obfuscated.force_encoding(::Encoding::ASCII_8BIT)
        end
        key_bytes = config.license_bytes
        index = 0
        text.each_byte{|byte|
          obfuscated.concat((byte ^ key_bytes[index % 13].to_i))
          index+=1
        }

        [obfuscated].pack("m0").gsub("\n", '')
      end

      def browser_monitoring_transaction_name
        current_timings.transaction_name || ::NewRelic::Agent::UNKNOWN_METRIC
      end

      def current_transaction
        NewRelic::Agent::TransactionState.get.transaction || @@dummy_txn
      end

      def current_timings
        NewRelic::Agent::TransactionState.get.timings
      end

      private

      # Check whether RUM header and footer should be generated.  Log the
      # reason if they shouldn't.
      def insert_js?
        if NewRelic::Agent.instance.beacon_configuration.nil?
          ::NewRelic::Agent.logger.debug "Beacon configuration is nil. Skipping browser instrumentation."
          false
        elsif ! NewRelic::Agent.instance.beacon_configuration.enabled?
          ::NewRelic::Agent.logger.debug "Beacon configuration is disabled. Skipping browser instrumentation."
          ::NewRelic::Agent.logger.debug NewRelic::Agent.instance.beacon_configuration.inspect
          false
        elsif Agent.config[:browser_key].nil? || Agent.config[:browser_key].empty?
          ::NewRelic::Agent.logger.debug "Browser key is not set. Skipping browser instrumentation."
          false
        elsif ! NewRelic::Agent.is_transaction_traced?
          ::NewRelic::Agent.logger.debug "Transaction is not traced. Skipping browser instrumentation."
          false
        elsif ! NewRelic::Agent.is_execution_traced?
          ::NewRelic::Agent.logger.debug "Execution is not traced. Skipping browser instrumentation."
          false
        elsif NewRelic::Agent::TransactionState.get.request_ignore_enduser
          ::NewRelic::Agent.logger.debug "Ignore end user for this transaction is set. Skipping browser instrumentation."
          false
        else
          true
        end
      end

      def generate_footer_js(config)
        if current_transaction.start_time
          footer_js_string(config)
        else
          ''
        end
      end

      def transaction_attribute(key)
        current_transaction.user_attributes[key] || ""
      end

      def tt_guid
        state = NewRelic::Agent::TransactionState.get
        return state.request_guid if include_guid?(state)
        ""
      end

      def include_guid?(state)
        state.request_token &&
          state.timings.app_time_in_seconds > state.transaction.apdex_t
      end

      def tt_token
        return NewRelic::Agent::TransactionState.get.request_token
      end

      def use_beta_js_agent?
        return Agent.config[:js_errors_beta] && !Agent.config[:js_agent_loader].to_s.empty?
      end

      # NOTE: This method may be overridden for internal prototyping, so should
      # remain stable.
      def header_js_string
        if (use_beta_js_agent?)
          html_safe_if_needed("\n<script type=\"text/javascript\">#{Agent.config[:js_agent_loader]}</script>")
        else
          NewRelic::Agent.instance.beacon_configuration.browser_timing_header
        end
      end

      # NOTE: This method may be overridden for internal prototyping, so should
      # remain stable.
      def footer_js_string(config)
        if (use_beta_js_agent?)
          js_data = {
            'txnParam' => config.finish_command,
            'beacon' => NewRelic::Agent.config[:beacon],
            'errorBeacon' => NewRelic::Agent.config[:error_beacon],
            'licenseKey' => NewRelic::Agent.config[:browser_key],
            'applicationID' => NewRelic::Agent.config[:application_id],
            'transactionName' => obfuscate(config, browser_monitoring_transaction_name),
            'queueTime' => current_timings.queue_time_in_millis,
            'applicationTime' => current_timings.app_time_in_millis,
            'ttGuid' => tt_guid,
            'agentToken' => tt_token,
            'user' => obfuscate(config, transaction_attribute(:user)),
            'account' => obfuscate(config, transaction_attribute(:account)),
            'product' => obfuscate(config, transaction_attribute(:product)),
            'agent' => NewRelic::Agent.config[:js_agent_file]
          }

          html_safe_if_needed("\n<script type=\"text/javascript\">window.NREUM||(NREUM={});NREUM.info=#{NewRelic.json_dump(js_data)}</script>")
        else
          obfuscated_transaction_name = obfuscate(config, browser_monitoring_transaction_name)

          user = obfuscate(config, transaction_attribute(:user))
          account = obfuscate(config, transaction_attribute(:account))
          product = obfuscate(config, transaction_attribute(:product))

          # This is slightly varied from other agents' RUM footer to ensure that
          # NREUMQ is defined. Our experimental header placement has some holes
          # where it could end up in a comment and not define NREUMQ as the footer
          # assumes. We protect against that here.
          html_safe_if_needed(%'<script type="text/javascript">if (typeof NREUMQ !== "undefined") { #{config.browser_timing_static_footer}NREUMQ.push(["#{config.finish_command}","#{Agent.config[:beacon]}","#{Agent.config[:browser_key]}","#{Agent.config[:application_id]}","#{obfuscated_transaction_name}",#{current_timings.queue_time_in_millis},#{current_timings.app_time_in_millis},new Date().getTime(),"#{tt_guid}","#{tt_token}","#{user}","#{account}","#{product}"]);}</script>')
        end
      end

      def html_safe_if_needed(string)
        if string.respond_to?(:html_safe)
          string.html_safe
        else
          string
        end
      end
    end
  end
end
