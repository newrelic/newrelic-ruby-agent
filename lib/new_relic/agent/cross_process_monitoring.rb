require 'new_relic/rack/agent_hooks'

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

          timings = NewRelic::Agent::BrowserMonitoring.timings
          set_response_headers(request_headers, response_headers, timings)
          record_metrics(id, timings)
        end
      end


      def set_response_headers(request_headers, response_headers, timings)
        response_headers['X-NewRelic-App-Data'] = build_payload(request_headers, timings)
      end

      def build_payload(request_headers, timings)
        content_length = content_length_from_request(request_headers)

        # FIXME the transaction name might not be properly encoded.  use a json generator
        payload = %[["#{NewRelic::Agent.instance.cross_process_id}","#{timings.transaction_name}",#{timings.queue_time_in_seconds},#{timings.app_time_in_seconds},#{content_length}] ]
        payload = obfuscate_with_key(payload)
      end

      def record_metrics(id, timings)
        return if id == ""

        metric = NewRelic::Agent.instance.stats_engine.get_stats_no_scope("ClientApplication/#{decode_with_key(id)}/all")
        metric.record_data_point(timings.app_time_in_seconds)
      end

      def obfuscate_with_key(text)
        Base64.encode64(encode_with_key(text)).chomp
      end

      def decode_with_key(text)
        encode_with_key(Base64.decode64(text))
      end

      def id_from_request(request)
        from_headers(request, *%w{X-NewRelic-ID HTTP_X_NEWRELIC_ID X_NEWRELIC_ID})
      end

      def content_length_from_request(request)
        from_headers(request, *%w{Content-Length}) || -1
      end

      def wireup_rack_middleware
        NewRelic::Agent.logger.debug("Wiring up Cross Process monitoring to Agent Hooks after finished configuring")
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

      def from_headers(request, *try_keys)
        # For lookups, upcase all our keys on both sides just to be safe
        try_keys.map!(&:upcase)
        try_keys.each do |header|
          found_key = request.keys.find { |k| k.upcase == header }
          return request[found_key] unless found_key.nil?
        end
        nil
      end

    end
  end
end
