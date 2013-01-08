require 'new_relic/rack/agent_hooks'
require 'new_relic/agent/thread'

module NewRelic
  module Agent
    class CrossProcessMonitor

      def initialize
        @trusted_ids = []

        Agent.config.subscribe_finished_configuring do
          finish_setup(Agent.config)
          wireup_events
        end
      end

      def finish_setup(config)
        @cross_process_id = config[:cross_process_id]
        @encoding_key = config[:encoding_key]
        @encoding_bytes = get_bytes(@encoding_key) unless @encoding_key.nil?
        @trusted_ids = config[:trusted_account_ids] || []
      end

      # Expected sequence of events:
      #   :before_call will save our cross process request id to the thread
      #   :start_transaction will get called when a transaction starts up
      #   :after_call will write our response headers/metrics and clean up the thread
      def wireup_events
        NewRelic::Agent.logger.debug("Wiring up Cross Process monitoring to events after finished configuring")

        NewRelic::Rack::AgentHooks.subscribe(:before_call) do |env|
          self.save_cross_process_request_id(env)
        end

        NewRelic::Agent::StatsEngine.subscribe(:start_transaction) do |name|
          self.set_custom_parameters
        end

        NewRelic::Rack::AgentHooks.subscribe(:after_call) do |env, (status_code, headers, body)|
          self.insert_response_header(env, headers)
        end
      end

      # Because we aren't in the right spot when our transaction actually
      # starts, hold cross_process_request_id we get thread local until then.
      THREAD_ID_KEY = :newrelic_cross_process_request_id

      def save_cross_process_request_id(request_headers)
        if should_process_request(request_headers)
          NewRelic::Agent::AgentThread.current[THREAD_ID_KEY] = decoded_id(request_headers)
        end
      end

      def clear_cross_process_request_id
        NewRelic::Agent::AgentThread.current[THREAD_ID_KEY] = nil
      end

      def cross_process_request_id
        NewRelic::Agent::AgentThread.current[THREAD_ID_KEY]
      end

      def insert_response_header(request_headers, response_headers)
        unless cross_process_request_id.nil?
          timings = NewRelic::Agent::BrowserMonitoring.timings

          set_response_headers(request_headers, response_headers, timings)
          record_metrics(cross_process_request_id, timings)

          clear_cross_process_request_id
        end
      end

      def should_process_request(request_headers)
        return Agent.config[:'cross_process.enabled'] &&
            @cross_process_id &&
            trusts?(request_headers)
      end

      # Expects an ID of format "12#345", and will only accept that!
      def trusts?(request)
        id = decoded_id(request)
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
      end

      def set_custom_parameters
        # We expect to get the before call to set the id (if we have it) before
        # this, and then write our custom parameter when the transaction starts
        NewRelic::Agent.add_custom_parameters(:client_cross_process_id => cross_process_request_id) unless cross_process_request_id.nil?
      end

      def record_metrics(id, timings)
        metric = NewRelic::Agent.instance.stats_engine.get_stats_no_scope("ClientApplication/#{id}/all")
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

      def decoded_id(request)
        encoded_id = from_headers(request, NEWRELIC_ID_HEADER_KEYS)
        return "" if encoded_id.nil?

        decode_with_key(encoded_id)
      end

      def content_length_from_request(request)
        from_headers(request, CONTENT_LENGTH_HEADER_KEYS) || -1
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
