module NewRelic
  module Agent

    class Thread < ::Thread
      def initialize(label)
        ::NewRelic::Agent.logger.debug("Creating New Relic thread: #{label}")
        self[:newrelic_label] = label
        super
      end

      def self.bucket_thread(thread, profile_agent_code)
        if thread.key?(:newrelic_label)
          return profile_agent_code ? :agent : :ignore
        elsif !thread[:newrelic_metric_frame].nil?
          thread[:newrelic_metric_frame].request.nil? ? :background : :request
        else
          :other
        end
      end

      def self.scrub_backtrace(thread, profile_agent_code)
        return thread.backtrace if profile_agent_code
        thread.backtrace.select {|t| t !~ /\/newrelic_rpm-\d/ }
      end
    end
  end
end
