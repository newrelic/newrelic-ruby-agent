module NewRelic
  module Agent

    class AgentThread < ::Thread
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
        begin
          bt = thread.backtrace
        rescue Exception => e
          ::NewRelic::Agent.logger.debug("Failed to backtrace #{thread.inspect}: #{e.class.name}: #{e.to_s}")
        end
        return nil unless bt
        profile_agent_code ? bt : bt.select { |t| t !~ /\/newrelic_rpm-\d/ }
      end
    end
  end
end
