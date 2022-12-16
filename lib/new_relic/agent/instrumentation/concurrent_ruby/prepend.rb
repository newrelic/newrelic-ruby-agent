# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module ConcurrentRuby::Prepend
    include NewRelic::Agent::Instrumentation::ConcurrentRuby

    def post(*args, &task)
      traced_task = traced_block_concurrent(*args, &task)
      post_with_new_relic(*args) { super(*args, &traced_task) }
    end

    # this is basically just a copy of Tracer#thread_block_with_current_transaction with the segment name changed
    def traced_block_concurrent(*args, &block)
      current_txn = ::Thread.current[:newrelic_tracer_state].current_transaction if ::Thread.current[:newrelic_tracer_state] && ::Thread.current[:newrelic_tracer_state].is_execution_traced?
      traced_task = proc do
        begin
          if current_txn
            NewRelic::Agent::Tracer.state.current_transaction = current_txn
            # is this one just redundant?
            segment = NewRelic::Agent::Tracer.start_segment(name: "Ruby/Inner_concurrent_ruby/#{::Thread.current.object_id}")
          end
          yield(*args) if block.respond_to?(:call)
        ensure
          ::NewRelic::Agent::Transaction::Segment.finish(segment)
        end
      end
    end
  end
end
