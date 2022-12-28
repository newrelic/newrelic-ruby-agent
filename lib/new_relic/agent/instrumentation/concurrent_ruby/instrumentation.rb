# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module ConcurrentRuby
    DEFAULT_NAME = 'Concurrent::ThreadPoolExecutor#post'
    TASK_NAME = 'Concurrent/Task'

    def post_with_new_relic(*args)
      segment = NewRelic::Agent::Tracer.start_segment(name: DEFAULT_NAME)
      begin
        yield
      ensure
        ::NewRelic::Agent::Transaction::Segment.finish(segment)
      end
    end

    def add_task_tracing(*args, &task)
      NewRelic::Agent::Tracer.thread_block_with_current_transaction(
        *args,
        segment_name: TASK_NAME,
        parent: NewRelic::Agent::Tracer.current_segment,
        &task
      )
    end
  end
end
