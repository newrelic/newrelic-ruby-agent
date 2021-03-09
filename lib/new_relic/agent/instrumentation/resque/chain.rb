# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.


module NewRelic::Agent::Instrumentation
  module Resque
    module Chain 
      def self.instrument!
        ::Resque::Job.class_eval do
          include NewRelic::Agent::Instrumentation::ControllerInstrumentation

          alias_method :perform_without_instrumentation, :perform
  
          def perform
            begin
              perform_action_with_newrelic_trace(
                :name => 'perform',
                :class_name => self.payload_class,
                :category => 'OtherTransaction/ResqueJob') do
  
                NewRelic::Agent::Transaction.merge_untrusted_agent_attributes(
                  args,
                  :'job.resque.args',
                  NewRelic::Agent::AttributeFilter::DST_NONE)
  
                perform_without_instrumentation
              end
            ensure
              # Stopping the event loop before flushing the pipe.
              # The goal is to avoid conflict during write.
              NewRelic::Agent.agent.stop_event_loop
              NewRelic::Agent.agent.flush_pipe_data
            end
          end
        end
      end
    end
  end
end
