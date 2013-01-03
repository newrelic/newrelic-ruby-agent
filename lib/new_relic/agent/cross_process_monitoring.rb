module NewRelic
  module Agent

    class CrossProcessMonitor

      def initialize
        Agent.config.subscribe_finished_configuring do
          wireup_rack_middleware
        end
      end

      def insert_response_header(request_headers, response_headers)
        if Agent.config[:'cross_process.enabled'] &&
            NewRelic::Agent.instance.cross_process_id &&
            (id = id_from_request(request_headers))

          content_length = -1
          timings = NewRelic::Agent::BrowserMonitoring.timings

          # FIXME the transaction name might not be properly encoded.  use a json generator
          payload = %[["#{NewRelic::Agent.instance.cross_process_id}","#{timings.transaction_name}",#{timings.queue_time_in_millis},#{timings.app_time_in_millis},#{content_length}] ]
          payload = obfuscate_with_key(payload)

          response_headers['X-NewRelic-App-Data'] = payload

          #FIXME generate ClientApplication metric.  id must be decoded first
          # String metricName = MessageFormat.format("ClientApplication/{0}/all", id);
        end
      end

      def obfuscate_with_key(text)
        Base64.encode64(encode_with_key(text)).gsub("\n", '')
      end

      def decode_with_key(text)
        encode_with_key(Base64.decode64(text))
      end

      def id_from_request(request)
        %w{X-NewRelic-ID HTTP_X_NEWRELIC_ID X_NEWRELIC_ID}.each do |header|
          return request[header] if request.has_key?(header)
        end
        nil
      end

      def wireup_rack_middleware
        NewRelic::Rack::AgentHooks.subscribe(:after_call) do |env, response|
          self.insert_response_header(env, response[1])
        end
      end


      private

      def encode_with_key(text)
        key_bytes =  NewRelic::Agent.instance.cross_process_encoding_bytes

        encoded = ""
        index = 0
        text.each_byte{|byte|
          encoded.concat((byte ^ key_bytes[index % key_bytes.length].to_i))
          index+=1
        }
        encoded
      end
    end
  end
end
