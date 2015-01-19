# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/inbound_request_monitor'

module NewRelic
  module Agent
    class SyntheticsMonitor < InboundRequestMonitor
      SYNTHETICS_HEADER_KEY  = 'HTTP_X_NEWRELIC_SYNTHETICS'.freeze

      SUPPORTED_VERSION = 1
      EXPECTED_PAYLOAD_LENGTH = 5

      def on_finished_configuring(events)
        events.subscribe(:before_call, &method(:on_before_call))
      end

      def on_before_call(request) #THREAD_LOCAL_ACCESS
        encoded_header = request[SYNTHETICS_HEADER_KEY]
        return unless encoded_header

        incoming_payload = deserialize_header(encoded_header, SYNTHETICS_HEADER_KEY)

        return unless incoming_payload &&
            is_valid_payload?(incoming_payload) &&
            is_supported_version?(incoming_payload) &&
            is_trusted?(incoming_payload)

        state = NewRelic::Agent::TransactionState.tl_get
        txn = state.current_transaction
        txn.raw_synthetics_header = encoded_header
        txn.synthetics_payload    = incoming_payload
      end

      def is_supported_version?(incoming_payload)
        incoming_payload.first == SUPPORTED_VERSION
      end

      def is_trusted?(incoming_payload)
        account_id = incoming_payload[1]
        NewRelic::Agent.config[:trusted_account_ids].include?(account_id)
      end

      def is_valid_payload?(incoming_payload)
        incoming_payload.length == EXPECTED_PAYLOAD_LENGTH
      end
    end
  end
end
