# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module ConcurrentRuby
    SEGMENT_NAME = 'Concurrent/Task'
    SUPPORTABILITY_METRIC = 'Supportability/ConcurrentRuby/Invoked'

    def add_task_tracing(*args, &task)
      NewRelic::Agent.record_metric_once(SUPPORTABILITY_METRIC)

      NewRelic::Agent::Tracer.thread_block_with_current_transaction(
        *args,
        segment_name: SEGMENT_NAME,
        parent: NewRelic::Agent::Tracer.current_segment,
        &task
      )
    end
  end
end
