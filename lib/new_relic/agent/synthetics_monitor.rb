# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class SyntheticsMonitor

      SYNTHETICS_HEADER_KEY = 'X-NewRelic-Synthetics'.freeze
      SUPPORTED_VERSION = 1

      def initialize(events = nil)
        # When we're starting up for real in the agent, we get passed the events
        # Other spots can pull from the agent, during startup the agent doesn't exist yet!
        events ||= Agent.instance.events

        events.subscribe(:finished_configuring) do
          on_finished_configuring(events)
        end
      end

      def on_finished_configuring(events)
        @obfuscator = NewRelic::Agent::Obfuscator.new(NewRelic::Agent.config[:encoding_key])
        events.subscribe(:before_call, &method(:on_before_call))
      end

      def on_before_call(request)
        incoming_payload = decode_payload(request)
        return unless incoming_payload &&
            is_supported_version?(incoming_payload) &&
            is_trusted?(incoming_payload)

        NewRelic::Agent::TransactionState.tl_get.synthetics_info = incoming_payload
      end

      def decode_payload(request)
        encoded_header = request[SYNTHETICS_HEADER_KEY]
        return nil unless encoded_header

        decoded_header = @obfuscator.deobfuscate(encoded_header)
        NewRelic::JSONWrapper.load(decoded_header)
      end

      def is_supported_version?(incoming_payload)
        incoming_payload.first == SUPPORTED_VERSION
      end

      def is_trusted?(incoming_payload)
        account_id = incoming_payload[1]
        NewRelic::Agent.config[:trusted_account_ids].include?(account_id)
      end
    end
  end
end
