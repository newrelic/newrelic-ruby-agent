# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Resque
    include NewRelic::Agent::Instrumentation::ControllerInstrumentation

    INSTRUMENTATION_NAME = NewRelic::Agent.base_name(name)

    def with_tracing
      NewRelic::Agent.record_instrumentation_invocation(INSTRUMENTATION_NAME)

      begin
        NewRelic::Agent.logger.debug("PAISLEY: start time before perform_action_with_newrelic_trace in Resque: #{Process.clock_gettime(Process::CLOCK_REALTIME)}")
        NewRelic::Agent.logger.debug("PAISLEY: stats_engine.stats_hash.started_at: #{NewRelic::Agent.agent&.stats_engine&.stats_hash&.started_at}")
        perform_action_with_newrelic_trace(
          :name => 'perform',
          :class_name => self.payload_class,
          :category => 'OtherTransaction/ResqueJob'
        ) do
          NewRelic::Agent::Transaction.merge_untrusted_agent_attributes(
            args,
            :'job.resque.args',
            NewRelic::Agent::AttributeFilter::DST_NONE
          )
        NewRelic::Agent.logger.debug("PAISLEY: time after perform_action_with_newrelic_trace in Resque: #{Process.clock_gettime(Process::CLOCK_REALTIME)}")
          yield
        end
      ensure
        # Stopping the event loop before flushing the pipe.
        # The goal is to avoid conflict during write.
        if NewRelic::Agent::Instrumentation::Resque::Helper.resque_fork_per_job?
          NewRelic::Agent.agent.stop_event_loop
          NewRelic::Agent.agent.flush_pipe_data
        end
      end
    end
  end
end
