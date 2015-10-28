# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/instrumentation/controller_instrumentation'

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

          def invoke_job
            options = { :category => 'OtherTransaction/DelayedJob' }

            if payload_object.is_a? ::Delayed::PerformableMethod
              options[:path] = payload_object.object.is_a?(Class) ?
                  "#{payload_object.object}.#{payload_object.method_name}" :
                  "#{payload_object.object.class}##{payload_object.method_name}"
            else
              options[:path] = payload_object.class.name
            end

            perform_action_with_newrelic_trace(options) do
              invoke_job_without_new_relic
            end
          end
        end
      end
    end
  end
end
