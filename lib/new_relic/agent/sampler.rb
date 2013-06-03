# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
#
# A Sampler is used to capture meaningful metrics in a background thread
# periodically.  They will be invoked about once a minute, each time the agent
# sends data to New Relic's servers.
#
# Samplers can be added to New Relic by subclassing NewRelic::Agent::Sampler.
# Instances are created when the agent is enabled and installed.  Subclasses
# are registered for instantiation automatically.
module NewRelic
  module Agent
    class Sampler

      # Exception denotes a sampler is not available and it will not be registered.
      class Unsupported < StandardError;  end

      attr_reader :id
      @sampler_classes = []

      def self.inherited(subclass)
        @sampler_classes << subclass
      end

      # Override with check.  Called before instantiating.
      def self.supported_on_this_platform?
        true
      end

      def self.sampler_classes
        @sampler_classes
      end

      def initialize(id)
        @id = id
      end

      def poll
        raise "Implement in the subclass"
      end
    end
  end
end
