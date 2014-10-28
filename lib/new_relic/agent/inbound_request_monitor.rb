# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# This class serves as the base for objects wanting to monitor and respond to
# incoming web requests. Examples include cross application tracing and
# synthetics.
#
# Subclasses are expected to define on_finished_configuring(events) which will
# be called when the agent is fully configured. That method is expected to
# subscribe to the necessary request events, such as before_call and after_call
# for the monitor to do its work.
module NewRelic
  module Agent
    class InboundRequestMonitor

      attr_reader :obfuscator

      def initialize(events)
        events.subscribe(:finished_configuring) do
          # This requires :encoding_key, so must wait until :finished_configuring
          setup_obfuscator
          on_finished_configuring(events)
        end
      end

      def setup_obfuscator
        @obfuscator = NewRelic::Agent::Obfuscator.new(NewRelic::Agent.config[:encoding_key])
      end

      def deserialize_header(encoded_header, key)
        decoded_header = obfuscator.deobfuscate(encoded_header)
        NewRelic::JSONWrapper.load(decoded_header)
      rescue => err
        # If we have a failure of any type here, just return nil and carry on
        NewRelic::Agent.logger.debug("Failure deserializing encoded header '#{key}' in #{self.class}, #{err.class}, #{err.message}")
        nil
      end
    end
  end
end
