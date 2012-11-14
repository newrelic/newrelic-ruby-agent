module NewRelic
  module Agent

    class Thread < ::Thread
      def initialize(label)
        NewRelic::Agent.logger.debug("Creating New Relic thread: #{label}")
        self[:newrelic_label] = label
        super
      end

      def self.is_new_relic?(thread)
        thread.key?(:newrelic_label) 
      end
    end

  end
end
