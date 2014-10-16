# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class InboundRequestMonitor

      attr_reader :obfuscator

      def initialize(events = nil)
        # When we're starting up for real in the agent, we get passed the events
        # Other spots can pull from the agent, during startup the agent doesn't exist yet!
        events ||= Agent.instance.events

        events.subscribe(:finished_configuring) do
          # This requires :encoding_key, so must wait until :finished_configuring
          setup_obfuscator

          on_finished_configuring(events)
        end
      end

      def setup_obfuscator
        @obfuscator = NewRelic::Agent::Obfuscator.new(NewRelic::Agent.config[:encoding_key])
      end

      def deserialize_header(encoded_header)
        decoded_header = obfuscator.deobfuscate(encoded_header)
        NewRelic::JSONWrapper.load(decoded_header)
      end

      # For lookups, upcase all our keys on both sides just to be safe
      def from_headers(request, try_keys)
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
