# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class SyntheticsMonitor

      SYNTHETICS_HEADER_KEY = 'X-NewRelic-Synthetics'.freeze

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
        events.subscribe(:before_call) do |request|
          encoded_header = request[SYNTHETICS_HEADER_KEY]
          if encoded_header
            decoded_header = @obfuscator.deobfuscate(encoded_header)
            loaded_header  = NewRelic::JSONWrapper.load(decoded_header)
            NewRelic::Agent::TransactionState.tl_get.synthetics_info = loaded_header
          end
        end
      end
    end
  end
end
