# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic
  module Agent
    module Instrumentation
      module ThreadMonitor
        attr_reader :nr_parent_thread_id

        def initialize_with_newrelic_tracing
          @nr_parent_thread_id = ::Thread.current.object_id
          yield
        end

        def add_thread_tracing(*args, &block)
          return block unless NewRelic::Agent.config[:'instrumentation.thread.tracing']

          instrumentation = ::Thread.current[:newrelic_tracer_state]
          Proc.new do
            begin
              ::Thread.current[:newrelic_tracer_state] = instrumentation
              segment = NewRelic::Agent::Tracer.start_segment(name: "Ruby/Thread/#{::Thread.current.object_id}")
              block.call(*args) if block.respond_to?(:call)
            ensure
              segment.finish if segment
            end
          end
        end
      end
    end
  end
end
