module NewRelic
  module Agent

    class Thread < ::Thread
      def initialize(label)
        NewRelic::Agent.logger.debug("Creating New Relic thread: #{label}")
        self[:newrelic_label] = label
        super
      end

      def self.bucket_thread(thread, profile_agent_code)
        if thread.key?(:newrelic_label)
          return profile_agent_code ? :agent : :ignore
        elsif thread.key?(:newrelic_metric_frame)
          thread[:newrelic_metric_frame].request.nil? ? :background : :request
        else
          :other
        end
      end
    end
  end
end
