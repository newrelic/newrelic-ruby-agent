require 'new_relic/rack/agent_hooks'

module NewRelic
  module Agent

    class CrossProcessMonitor

      def initialize
        @trusted_ids = []

        Agent.config.subscribe_finished_configuring do
          finish_setup(Agent.config)
          wireup_rack_middleware
        end
      end

      def finish_setup(config)
        @cross_process_id = config[:cross_process_id]
        @encoding_key = config[:encoding_key]
        @encoding_bytes = get_bytes(@encoding_key) unless @encoding_key.nil?
        @trusted_ids = config[:trusted_account_ids]
      end

      def insert_response_header(request_headers, response_headers)
        if Agent.config[:'cross_process.enabled'] &&
            @cross_process_id &&
            (encoded_id = id_from_request(request_headers))

          decoded_id = decode_with_key(encoded_id)
          return if !trusts?(decoded_id)

          timings = NewRelic::Agent::BrowserMonitoring.timings
          set_response_headers(request_headers, response_headers, timings)
          set_metrics(decoded_id, timings)
          set_custom_parameter(decoded_id)
        end
      end

      # Expects an ID of format "12#345", and will only accept that!
      def trusts?(id)
        split_id = id.match(/(\d+)#\d+/)
        return false if split_id.nil?

        @trusted_ids.include?(split_id.captures.first.to_i)
      end

      def set_response_headers(request_headers, response_headers, timings)
        response_headers['X-NewRelic-App-Data'] = build_payload(request_headers, timings)
      end

      def build_payload(request_headers, timings)
        content_length = content_length_from_request(request_headers)

        # FIXME The transaction name might not be properly encoded.  use a json generator
        # For now we just handle quote characters by dropping them
        transaction_name = timings.transaction_name.gsub(/["']/, "")

        payload = %[["#{@cross_process_id}","#{transaction_name}",#{timings.queue_time_in_seconds},#{timings.app_time_in_seconds},#{content_length}] ]
        payload = obfuscate_with_key(payload)
        NewRelic::Agent.logger.debug("Payload was :'#{payload}'")
        payload
      end

      def set_metrics(id, timings)
        metric = NewRelic::Agent.instance.stats_engine.get_stats_no_scope("ClientApplication/#{id}/all")
        metric.record_data_point(timings.app_time_in_seconds)
      end

      def set_custom_parameter(id)
        NewRelic::Agent::Instrumentation::MetricFrame.add_custom_parameters(:client_cross_process_id => id)
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

      # Ruby 1.8.6 doesn't support the bytes method on strings.
      def get_bytes(value)
        return [] if value.nil?

        bytes = []
        value.each_byte do |b|
          bytes << b
        end
        bytes
      end

      def encode_with_key(text)
        key_bytes =  @encoding_bytes

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
