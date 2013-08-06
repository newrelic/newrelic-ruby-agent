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
          if self.instance_methods.include?('name') || self.instance_methods.include?(:name)
            add_transaction_tracer "invoke_job", :category => 'OtherTransaction/DelayedJob', :path => '#{self.name}'
          else
            add_transaction_tracer "invoke_job", :category => 'OtherTransaction/DelayedJob'
          end
        end
      end
    end
  end
end
