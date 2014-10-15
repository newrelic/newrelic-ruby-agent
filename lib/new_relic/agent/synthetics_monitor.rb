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
        encoded_header = request[SYNTHETICS_HEADER_KEY]
        if encoded_header
          decoded_header = @obfuscator.deobfuscate(encoded_header)
          incoming_payload  = NewRelic::JSONWrapper.load(decoded_header)

          if is_supported_version?(incoming_payload)
            NewRelic::Agent::TransactionState.tl_get.synthetics_info = incoming_payload
          end
        end
      end

      def is_supported_version?(incoming_payload)
        incoming_payload.first == SUPPORTED_VERSION
      end
    end
  end
end
