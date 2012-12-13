require 'base64'
require 'new_relic/agent/beacon_configuration'
module NewRelic
  module Agent
    # This module contains support for Real User Monitoring - the
    # javascript generation and configuration
    module BrowserMonitoring
      class DummyMetricFrame
        def initialize
          @attributes = {}
        end

        def user_attributes
          @attributes
        end

        def queue_time
          0.0
        end
      end

      @@dummy_metric_frame = DummyMetricFrame.new

      # This method returns a string suitable for inclusion in a page
      # - known as 'manual instrumentation' for Real User
      # Monitoring. Can return either a script tag with associated
      # javascript, or in the case of disabled Real User Monitoring,
      # an empty string
      #
      # This is the header string - it should be placed as high in the
      # page as is reasonably possible - that is, before any style or
      # javascript inclusions, but after any header-related meta tags
      def browser_timing_header
        if insert_js?
          NewRelic::Agent.instance.beacon_configuration.browser_timing_header
        else
          ""
        end
      end

      # This method returns a string suitable for inclusion in a page
      # - known as 'manual instrumentation' for Real User
      # Monitoring. Can return either a script tag with associated
      # javascript, or in the case of disabled Real User Monitoring,
      # an empty string
      #
      # This is the footer string - it should be placed as low in the
      # page as is reasonably possible.
      def browser_timing_footer
        if insert_js?
          generate_footer_js(NewRelic::Agent.instance.beacon_configuration)
        else
          ""
        end
      end

      module_function

      def obfuscate(config, text)
        obfuscated = ""
        key_bytes = config.license_bytes
        index = 0
        text.each_byte{|byte|
          obfuscated.concat((byte ^ key_bytes[index % 13].to_i))
          index+=1
        }

        [obfuscated].pack("m0").gsub("\n", '')
      end

      def browser_monitoring_transaction_name
        NewRelic::Agent::TransactionInfo.get.transaction_name
      end

      def browser_monitoring_queue_time
        clamp_to_positive((current_metric_frame.queue_time.to_f * 1000.0).round)
      end

      def browser_monitoring_app_time
        clamp_to_positive(((Time.now - browser_monitoring_start_time).to_f * 1000.0).round)
      end

      def current_metric_frame
        Thread.current[:last_metric_frame] || @@dummy_metric_frame
      end

      def clamp_to_positive(value)
        return 0.0 if value < 0
        value
      end

      def browser_monitoring_start_time
        NewRelic::Agent::TransactionInfo.get.start_time
      end

      def insert_mobile_response_header(request, response)
        if mobile_header_found_in?(request) &&
            NewRelic::Agent.instance.beacon_configuration

          config = NewRelic::Agent.instance.beacon_configuration

          response['X-NewRelic-Beacon-Url'] = beacon_url(request)

          payload = %[ ["#{Agent.config[:application_id]}","#{obfuscate(config, browser_monitoring_transaction_name)}",#{browser_monitoring_queue_time},#{browser_monitoring_app_time}] ]
          response['X-NewRelic-App-Server-Metrics'] = payload
        end
      end

      def mobile_header_found_in?(request)
        headers = ['HTTP_X_NEWRELIC_MOBILE_TRACE', 'X_NEWRELIC_MOBILE_TRACE',
                   'X-NewRelic-Mobile-Trace']
        headers.inject(false){|i,m| i || (request.env[m] == 'true')}
      end

      def beacon_url(request)
        "#{request.scheme || 'http'}://#{Agent.config[:beacon]}/mobile/1/#{Agent.config[:browser_key]}"
      end

      private

      # Check whether RUM header and footer should be generated.  Log the
      # reason if they shouldn't.
      def insert_js?
        if NewRelic::Agent.instance.beacon_configuration.nil?
          NewRelic::Agent.logger.debug "Beacon configuration is nil. Skipping browser instrumentation."
          false
        elsif ! NewRelic::Agent.instance.beacon_configuration.enabled?
          NewRelic::Agent.logger.debug "Beacon configuration is disabled. Skipping browser instrumentation."
          NewRelic::Agent.logger.debug NewRelic::Agent.instance.beacon_configuration.inspect
          false
        elsif Agent.config[:browser_key].nil? || Agent.config[:browser_key].empty?
          NewRelic::Agent.logger.debug "Browser key is not set. Skipping browser instrumentation."
          false
        elsif ! NewRelic::Agent.is_transaction_traced?
          NewRelic::Agent.logger.debug "Transaction is not traced. Skipping browser instrumentation."
          false
        elsif ! NewRelic::Agent.is_execution_traced?
          NewRelic::Agent.logger.debug "Execution is not traced. Skipping browser instrumentation."
          false
        elsif NewRelic::Agent::TransactionInfo.get.ignore_end_user?
          NewRelic::Agent.logger.debug "Ignore end user for this transaction is set. Skipping browser instrumentation."
          false
        else
          true
        end
      end

      def generate_footer_js(config)
        if browser_monitoring_start_time
          footer_js_string(config)
        else
          ''
        end
      end

      def metric_frame_attribute(key)
        current_metric_frame.user_attributes[key] || ""
      end

      def tt_guid
        txn = NewRelic::Agent::TransactionInfo.get
        return txn.guid if txn.include_guid?
        ""
      end

      def tt_token
        return NewRelic::Agent::TransactionInfo.get.token
      end

      def footer_js_string(config)
        obfuscated_transaction_name = obfuscate(config, browser_monitoring_transaction_name)

        user = obfuscate(config, metric_frame_attribute(:user))
        account = obfuscate(config, metric_frame_attribute(:account))
        product = obfuscate(config, metric_frame_attribute(:product))

        html_safe_if_needed(%'<script type="text/javascript">#{config.browser_timing_static_footer}NREUMQ.push(["#{config.finish_command}","#{Agent.config[:beacon]}","#{Agent.config[:browser_key]}","#{Agent.config[:application_id]}","#{obfuscated_transaction_name}",#{browser_monitoring_queue_time},#{browser_monitoring_app_time},new Date().getTime(),"#{tt_guid}","#{tt_token}","#{user}","#{account}","#{product}"]);</script>')
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
