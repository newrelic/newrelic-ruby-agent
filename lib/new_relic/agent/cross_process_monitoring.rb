require 'base64'
module NewRelic
  module Agent
    module CrossProcessMonitoring
      #start copied from BrowserMonitoring

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

      #end

      module_function

      #start copy from BrowserMonitoring

      def browser_monitoring_transaction_name
        NewRelic::Agent::TransactionInfo.get.transaction_name
      end

      def browser_monitoring_queue_time_in_seconds
        clamp_to_positive((current_metric_frame.queue_time.to_f).round)
      end

      def browser_monitoring_app_time_in_seconds
        clamp_to_positive(((Time.now - browser_monitoring_start_time).to_f).round)
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

      # end copy

      def obfuscate_with_key(text, key_bytes)
        obfuscated = ""
        index = 0
        text.each_byte{|byte|
          obfuscated.concat((byte ^ key_bytes[index % key_bytes.length].to_i))
          index+=1
        }

        [obfuscated].pack("m0").gsub("\n", '')
      end

      def insert_cross_process_response_header(request, response)

        if NewRelic::Agent.instance.cross_process_id && (id = cross_process_id_from_request(request))
          content_length = -1
          # FIXME the transaction name might not be properly encoded.  use a json generator
          payload = %[["#{NewRelic::Agent.instance.cross_process_id}","#{browser_monitoring_transaction_name}",#{browser_monitoring_queue_time_in_seconds},#{browser_monitoring_app_time_in_seconds},#{content_length}] ]
          payload = obfuscate_with_key payload, NewRelic::Agent.instance.cross_process_encoding_bytes

          response['X-NewRelic-App-Data'] = payload
          #FIXME generate ClientApplication metric.  id must be decoded first
          # String metricName = MessageFormat.format("ClientApplication/{0}/all", id);
        end
      end

      def cross_process_id_from_request(request)
        headers = ['X-NewRelic-ID', 'HTTP_X_NEWRELIC_ID', 'X_NEWRELIC_ID']
        headers.each do |header|
          id = request.env[header]
          return id if id
        end
        nil
      end

      private
    end
  end
end
