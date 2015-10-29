# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/instrumentation/controller_instrumentation'

module NewRelic
  module Agent
    module Instrumentation
      module DelayedJob
        module Naming
          module_function
          # NewRelic::Agent::Instrumentation::DelayedJob::Naming.name_from_payload
          def name_from_payload(payload_object)
            if payload_object.is_a? ::Delayed::PerformableMethod
              "#{object_name(payload_object)}#{delimiter(payload_object)}#{method_name(payload_object)}"
            else
              payload_object.class.name
            end
          end

          def object_name(payload_object)
            if payload_object.object.is_a?(Class)
              payload_object.object.to_s
            elsif payload_object.object.is_a?(String) && payload_object.object[0..4] == 'LOAD;'
              # Older versions of Delayed Job use a semicolon-delimited string to stash the class name.
              # The format of this string is "LOAD;<class name>;<ORM ID>
              payload_object.object.split(';')[1] || '(unknown class)'
            else
              payload_object.object.class.name
            end
          end

          def delimiter(payload_object)
            if payload_object.object.is_a?(Class)
              '.'
            else
              '#'
            end
          end

          # DelayedJob's interface for the async method's name varies across the gem's versions
          def method_name(payload_object)
            if payload_object.respond_to?(:method_name)
              payload_object.method_name
            else
              # early versions of Delayed Job override Object#method with the method name
              payload_object.method
            end
          end
        end
      end
    end
  end
end

DependencyDetection.defer do
  @name = :delayed_job

  depends_on do
    !NewRelic::Agent.config[:disable_dj]
  end

  depends_on do
    defined?(::Delayed) && defined?(::Delayed::Worker) && !NewRelic::Agent.config[:disable_dj]
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing DelayedJob instrumentation [part 1/2]'
  end

  executes do
    Delayed::Worker.class_eval do
      def initialize_with_new_relic(*args)
        initialize_without_new_relic(*args)
        worker_name = case
                      when self.respond_to?(:name) then self.name
                      when self.class.respond_to?(:default_name) then self.class.default_name
                      end
        NewRelic::DelayedJobInjection.worker_name = worker_name

        if defined?(::Delayed::Job) && ::Delayed::Job.method_defined?(:invoke_job)
          ::NewRelic::Agent.logger.info 'Installing DelayedJob instrumentation [part 2/2]'
          install_newrelic_job_tracer
          NewRelic::Control.instance.init_plugin :dispatcher => :delayed_job
        else
          NewRelic::Agent.logger.warn("Did not find a Delayed::Job class responding to invoke_job, aborting DJ instrumentation")
        end
      end

      alias initialize_without_new_relic initialize
      alias initialize initialize_with_new_relic

      def install_newrelic_job_tracer
        Delayed::Job.class_eval do
          include NewRelic::Agent::Instrumentation::ControllerInstrumentation

          alias_method :invoke_job_without_new_relic, :invoke_job

          def invoke_job(*args, &block)
            options = {
              :category => 'OtherTransaction/DelayedJob',
              :path => ::NewRelic::Agent::Instrumentation::DelayedJob::Naming.name_from_payload(payload_object)
            }

            perform_action_with_newrelic_trace(options) do
              invoke_job_without_new_relic(*args, &block)
            end
          end
        end
      end
    end
  end
end
