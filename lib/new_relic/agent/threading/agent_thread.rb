# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Threading

      class AgentThread < ::Thread
        def initialize(label)
          ::NewRelic::Agent.logger.debug("Creating New Relic thread: #{label}")
          self[:newrelic_label] = label
          super
        end

        def self.bucket_thread(thread, profile_agent_code)
          transaction_stack = TransactionState.for(thread).current_transaction_stack
          if thread.key?(:newrelic_label)
            return profile_agent_code ? :agent : :ignore
          elsif transaction_stack.respond_to?(:last) &&
            transaction_stack.last
            transaction_stack.last.request.nil? ? :background : :request
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
end
