# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.


DependencyDetection.defer do
  named :rake

  depends_on do
    defined?(::Rake) && ::NewRelic::Agent.config[:'rake.tasks'].any?
  end

  executes do
    ::NewRelic::Agent.logger.info  "Installing Rake instrumentation"
    ::NewRelic::Agent.logger.debug "Instrumenting Rake tasks: #{::NewRelic::Agent.config[:'rake.tasks']}"
  end

  executes do
    module Rake
      class Application
        alias_method :define_task_without_newrelic, :define_task
        def define_task(task_class, *args, &block)
          task = define_task_without_newrelic(task_class, *args, &block)
          NewRelic::Agent::Instrumentation::RakeInstrumentation.instrument_task(task)
          task
        end
      end
    end
  end
end

module NewRelic
  module Agent
    module Instrumentation
      module RakeInstrumentation
        def self.should_trace?(task)
          NewRelic::Agent.config[:'rake.tasks'].any? do |regex|
            regex.match(task.name)
          end
        end

        def self.instrument_task(task)
          return unless should_trace?(task)

          task.instance_eval do
            def invoke(*args, &block)
              NewRelic::Agent::Instrumentation::RakeInstrumentation.ensure_at_exit
              NewRelic::Agent::Instrumentation::RakeInstrumentation.instrument_execute_on_prereqs(self)

              state = NewRelic::Agent::TransactionState.tl_get
              NewRelic::Agent::Transaction.wrap(state, "OtherTransaction/Rake/invoke/#{self.name}", :rake)  do
                NewRelic::Agent::Instrumentation::RakeInstrumentation.record_attributes(args, self)
                super
              end
            end
          end
        rescue => e
          NewRelic::Agent.logger.error("Failure while instrumenting Rake task #{task}", e)
        end

        def self.instrument_execute_on_prereqs(task)
          task.prerequisite_tasks.each do |child_task|
            instrument_execute(child_task)
          end
        end

        def self.instrument_execute(task)
          return if task.instance_variable_get(:@__newrelic_instrumented_execute)

          task.instance_variable_set(:@__newrelic_instrumented_execute, true)
          task.instance_eval do
            def execute(*args, &block)
              NewRelic::Agent::MethodTracer.trace_execution_scoped("Rake/execute/#{self.name}") do
                super
              end
            end
          end

          instrument_execute_on_prereqs(task)
        end

        def self.record_attributes(args, task)
          named_args = name_the_args(args, task.arg_names)
          NewRelic::Agent::Transaction.merge_untrusted_agent_attributes(named_args,
                                                                        :'job.rake.args',
                                                                        NewRelic::Agent::AttributeFilter::DST_NONE)
        end

        # Expects literal args passed to the task and array of task names
        def self.name_the_args(args, names)
          result = {}
          args.zip(names).each_with_index do |(value, key), index|
            result[key || index.to_s] = value
          end
          result
        end

        def self.ensure_at_exit
          return if @installed_at_exit

          at_exit do
            # The agent's default at_exit might not default to installing, but
            # if we are running an instrumented rake task, we always want it.
            NewRelic::Agent.shutdown
          end

          @installed_at_exit = true
        end
      end
    end
  end
end
