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

        # FIXME The transaction name might not be properly encoded.  use a json generator
        # For now we just handle quote characters by dropping them
        transaction_name = timings.transaction_name.gsub(/["']/, "")

        payload = %[["#{NewRelic::Agent.instance.cross_process_id}","#{transaction_name}",#{timings.queue_time_in_seconds},#{timings.app_time_in_seconds},#{content_length}] ]
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

      NEWRELIC_ID_HEADER_KEYS = %w{X-NewRelic-ID HTTP_X_NEWRELIC_ID X_NEWRELIC_ID}
      CONTENT_LENGTH_HEADER_KEYS = %w{Content-Length HTTP_CONTENT_LENGTH CONTENT_LENGTH}

      def id_from_request(request)
        from_headers(request, NEWRELIC_ID_HEADER_KEYS)
      end

      def content_length_from_request(request)
        from_headers(request, CONTENT_LENGTH_HEADER_KEYS) || -1
      end

      def wireup_rack_middleware
        NewRelic::Agent.logger.debug("Wiring up Cross Process monitoring to Agent Hooks after finished configuring")
        NewRelic::Rack::AgentHooks.subscribe(:after_call) do |env, (status_code, headers, body)|
          self.insert_response_header(env, headers)
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

      def from_headers(request, try_keys)
        # For lookups, upcase all our keys on both sides just to be safe
        upcased_keys = try_keys.map(&:upcase)
        upcased_keys.each do |header|
          found_key = request.keys.find { |k| k.upcase == header }
          return request[found_key] unless found_key.nil?
        end
        nil
      end

    end
  end
end
