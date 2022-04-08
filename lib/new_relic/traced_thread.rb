# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  class TracedThread < Thread
    def initialize(*args, &block)
      # we should add metrics
      traced_block = create_traced_block(*args, block)
      super(*args, &traced_block)
    end

    def create_traced_block(*args, block)
      return block if NewRelic::Agent.config[:'instrumentation.thread.auto_instrument'] # if this is on, don't double trace

      instrumentation = ::Thread.current[:newrelic_tracer_state]
      Proc.new do |*args|
        ::Thread.current[:newrelic_tracer_state] = instrumentation
        segment = NewRelic::Agent::Tracer.start_segment(name: "Thread#{::Thread.current.object_id}")
        block.call(*args) if block.respond_to?(:call)
      ensure
        segment.finish if segment
      end
    end
  end
end
