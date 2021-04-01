# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Instrumentation
      module Rake
        module Tracer
          def invoke_with_newrelic_tracing(*args)
            unless NewRelic::Agent::Instrumentation::Rake.should_trace? name
              return yield
            end

            begin
              timeout = NewRelic::Agent.config[:'rake.connect_timeout']
              NewRelic::Agent.instance.wait_on_connect(timeout)
            rescue => e
              NewRelic::Agent.logger.error("Exception in wait_on_connect", e)
              return yield
            end

            NewRelic::Agent::Instrumentation::Rake.before_invoke_transaction(self)

            NewRelic::Agent::Tracer.in_transaction(name: "OtherTransaction/Rake/invoke/#{name}", category: :rake) do
              NewRelic::Agent::Instrumentation::Rake.record_attributes(args, self)
              yield
            end
          end
        end

        module_function

        def should_install?
          safe_from_third_party_gem?
        end

        def safe_from_third_party_gem?
          return true unless NewRelic::LanguageSupport.bundled_gem?("newrelic-rake")
          ::NewRelic::Agent.logger.info("Not installing New Relic supported Rake instrumentation because the third party newrelic-rake gem is present")
          false
        end

        def should_trace?(name)
          NewRelic::Agent.config[:'rake.tasks'].any? do |regex|
            regex.match(name)
          end
        end

        def instrument_execute_on_prereqs(task)
          task.prerequisite_tasks.each do |child_task|
            instrument_execute(child_task)
          end
        end

        def instrument_execute(task)
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

        def instrument_invoke_prerequisites_concurrently(task)
          task.instance_eval do
            def invoke_prerequisites_concurrently(*_)
              NewRelic::Agent::MethodTracer.trace_execution_scoped("Rake/execute/multitask") do
                prereqs = self.prerequisite_tasks.map(&:name).join(", ")
                if txn = ::NewRelic::Agent::Tracer.current_transaction
                  txn.current_segment.params[:statement] = NewRelic::Agent::Database.truncate_query("Couldn't trace concurrent prereq tasks: #{prereqs}")
                end
                super
              end
            end
          end
        end

        def before_invoke_transaction(task)
          ensure_at_exit

          # We can't represent overlapping operations yet, so if multitask just
          # make one node and annotate with prereq task names
          if task.application.options.always_multitask
            instrument_invoke_prerequisites_concurrently(task)
          else
            instrument_execute_on_prereqs(task)
          end
        rescue => e
          NewRelic::Agent.logger.error("Error during Rake task invoke", e)
        end

        def record_attributes(args, task)
          command_line = task.application.top_level_tasks.join(" ")
          NewRelic::Agent::Transaction.merge_untrusted_agent_attributes({ :command => command_line },
                                                                        :'job.rake',
                                                                        NewRelic::Agent::AttributeFilter::DST_NONE)
          named_args = name_the_args(args, task.arg_names)
          unless named_args.empty?
            NewRelic::Agent::Transaction.merge_untrusted_agent_attributes(named_args,
                                                                          :'job.rake.args',
                                                                          NewRelic::Agent::AttributeFilter::DST_NONE)
          end
        rescue => e
          NewRelic::Agent.logger.error("Error during Rake task attribute recording.", e)
        end

        # Expects literal args passed to the task and array of task names
        # If names are present without matching args, still sets them with nils
        def name_the_args(args, names)
          unfulfilled_names_length = names.length - args.length
          if unfulfilled_names_length > 0
            args.concat(Array.new(unfulfilled_names_length))
          end

          result = {}
          args.zip(names).each_with_index do |(value, key), index|
            result[key || index.to_s] = value
          end
          result
        end

        def ensure_at_exit
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