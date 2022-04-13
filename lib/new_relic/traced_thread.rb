# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  #
  # This class allows the state of a transaction to be passed to a Thread so that nested segments can be created from the operations performed within the Thread's block.
  # In order to have this functionality inserted into all threads automatically,
  # enable the `instrumentation.thread.tracing` configuration option in your newrelic.yml
  #
  # @api public
  class TracedThread < Thread
    #
    # Creates a new thread that will be traced by the agent.
    # Use this class the same as the Thread class
    #
    # @api public
    def initialize(*args, &block)
      NewRelic::Agent.record_api_supportability_metric(:traced_thread)
      traced_block = create_traced_block(*args, &block)
      super(*args, &traced_block)
    end

    def create_traced_block(*args, &block)
      return block if NewRelic::Agent.config[:'instrumentation.thread.tracing'] # if this is on, don't double trace

      instrumentation = ::Thread.current[:newrelic_tracer_state]
      Proc.new do
        begin
          ::Thread.current[:newrelic_tracer_state] = instrumentation
          segment = NewRelic::Agent::Tracer.start_segment(name: "Thread#{::Thread.current.object_id}")
          block.call(*args) if block.respond_to?(:call)
        ensure
          segment.finish if segment
        end
      end
    end
  end
end
