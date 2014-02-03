# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/rack/agent_hooks'
require 'new_relic/agent/transaction_state'
require 'new_relic/agent/threading/agent_thread'

module NewRelic
  module Agent

    class CrossAppMonitor

      NEWRELIC_ID_HEADER = 'X-NewRelic-ID'
      NEWRELIC_APPDATA_HEADER = 'X-NewRelic-App-Data'
      NEWRELIC_TXN_HEADER = 'X-NewRelic-Transaction'
      NEWRELIC_TXN_HEADER_KEYS = %W{
        #{NEWRELIC_TXN_HEADER} HTTP_X_NEWRELIC_TRANSACTION X_NEWRELIC_TRANSACTION
      }
      NEWRELIC_ID_HEADER_KEYS = %W{
        #{NEWRELIC_ID_HEADER} HTTP_X_NEWRELIC_ID X_NEWRELIC_ID
      }
      CONTENT_LENGTH_HEADER_KEYS = %w{Content-Length HTTP_CONTENT_LENGTH CONTENT_LENGTH}

      attr_reader :obfuscator

      def initialize(events = nil)
        # When we're starting up for real in the agent, we get passed the events
        # Other spots can pull from the agent, during startup the agent doesn't exist yet!
        events ||= Agent.instance.events

        events.subscribe(:finished_configuring) do
          on_finished_configuring
        end
      end

      def on_finished_configuring
        setup_obfuscator
        register_event_listeners
      end

      # Expected sequence of events:
      #   :before_call will save our cross application request id to the thread
      #   :start_transaction will get called when a transaction starts up
      #   :after_call will write our response headers/metrics and clean up the thread
      def register_event_listeners
        NewRelic::Agent.logger.
          debug("Wiring up Cross Application Tracing to events after finished configuring")

        events = Agent.instance.events
        events.subscribe(:before_call) do |env|
          if should_process_request(env)
            save_client_cross_app_id(env)
            save_referring_transaction_info(env)
          end
        end

        events.subscribe(:start_transaction) do
          set_transaction_custom_parameters
        end

        events.subscribe(:after_call) do |env, (status_code, headers, body)|
          insert_response_header(env, headers)
        end

        events.subscribe(:notice_error) do |_, options|
          set_error_custom_parameters(options)
        end
      end

      # This requires :encoding_key, so must wait until :finished_configuring
      def setup_obfuscator
        @obfuscator = NewRelic::Agent::Obfuscator.new(NewRelic::Agent.config[:encoding_key])
      end

      def save_client_cross_app_id(request_headers)
        TransactionState.get.client_cross_app_id = decoded_id(request_headers)
      end

      def clear_client_cross_app_id
        TransactionState.get.client_cross_app_id = nil
      end

      def client_cross_app_id
        TransactionState.get.client_cross_app_id
      end

      def save_referring_transaction_info(request_headers)
        txn_header = from_headers( request_headers, NEWRELIC_TXN_HEADER_KEYS ) or return
        txn_header = obfuscator.deobfuscate( txn_header )
        txn_info = NewRelic::JSONWrapper.load( txn_header )
        NewRelic::Agent.logger.debug "Referring txn_info: %p" % [ txn_info ]

        TransactionState.get.referring_transaction_info = txn_info
      end

      def client_referring_transaction_guid
        info = TransactionState.get.referring_transaction_info or return nil
        return info[0]
      end

      def client_referring_transaction_record_flag
        info = TransactionState.get.referring_transaction_info or return nil
        return info[1]
      end

      def insert_response_header(request_headers, response_headers)
        unless client_cross_app_id.nil?
          unless NewRelic::Agent::TransactionState.get.transaction.nil?
            NewRelic::Agent::Transaction.freeze_name
            timings = NewRelic::Agent::TransactionState.get.timings
            content_length = content_length_from_request(request_headers)

            set_response_headers(response_headers, timings, content_length)
            set_metrics(client_cross_app_id, timings)
          end
          clear_client_cross_app_id
        end
      end

      def should_process_request(request_headers)
        return cross_app_enabled? && trusts?(request_headers)
      end

      def cross_app_enabled?
        NewRelic::Agent::CrossAppTracing.cross_app_enabled?
      end

      # Expects an ID of format "12#345", and will only accept that!
      def trusts?(request)
        id = decoded_id(request)
        split_id = id.match(/(\d+)#\d+/)
        return false if split_id.nil?

        NewRelic::Agent.config[:trusted_account_ids].include?(split_id.captures.first.to_i)
      end

      def set_response_headers(response_headers, timings, content_length)
        response_headers[NEWRELIC_APPDATA_HEADER] = build_payload(timings, content_length)
      end

      def build_payload(timings, content_length)
        payload = [
          NewRelic::Agent.config[:cross_process_id],
          timings.transaction_name,
          timings.queue_time_in_seconds.to_f,
          timings.app_time_in_seconds.to_f,
          content_length,
          transaction_guid()
        ]
        payload = obfuscator.obfuscate(NewRelic::JSONWrapper.dump(payload))
      end

      def set_transaction_custom_parameters
        # We expect to get the before call to set the id (if we have it) before
        # this, and then write our custom parameter when the transaction starts
        NewRelic::Agent.add_custom_parameters(:client_cross_process_id => client_cross_app_id()) if client_cross_app_id()

        referring_guid = client_referring_transaction_guid()
        if referring_guid
          NewRelic::Agent.logger.debug "Referring transaction guid: %p" % [referring_guid]
          NewRelic::Agent.add_custom_parameters(:referring_transaction_guid => referring_guid)
        end
      end

      def set_error_custom_parameters(options)
        options[:client_cross_process_id] = client_cross_app_id() if client_cross_app_id()
        # [MG] TODO: Should the CAT metrics be set here too?
      end

      def set_metrics(id, timings)
        metric_name = "ClientApplication/#{id}/all"
        NewRelic::Agent.record_metric(metric_name, timings.app_time_in_seconds)
      end

      def decoded_id(request)
        encoded_id = from_headers(request, NEWRELIC_ID_HEADER_KEYS)
        return "" if encoded_id.nil?

        obfuscator.deobfuscate(encoded_id)
      end

      def content_length_from_request(request)
        from_headers(request, CONTENT_LENGTH_HEADER_KEYS) || -1
      end

      def transaction_guid
        NewRelic::Agent::TransactionState.get.request_guid
      end

      private

      def from_headers(request, try_keys)
        # For lookups, upcase all our keys on both sides just to be safe
        upcased_keys = try_keys.map{|k| k.upcase}
        upcased_keys.each do |header|
          found_key = request.keys.find { |k| k.upcase == header }
          return request[found_key] unless found_key.nil?
        end
        nil
      end

    end

  end
end
