require 'new_relic/agent/instrumentation/controller_instrumentation'

DependencyDetection.defer do
  depends_on do
    value = !NewRelic::Control.instance['disable_dj']
    NewRelic::Control.instance.log.info('Delayed Job instrumentation disabled, edit the "disable_dj" parameter in your newrelic.yml to change this') unless value
    value
  end

  depends_on do
    value = defined?(::Delayed) && defined?(::Delayed::Job)
    NewRelic::Control.instance.log.info('Delayed Job not defined, skipping instrumentation') unless value    
    value
  end

  executes do
    Delayed::Job.class_eval do
      NewRelic::Control.instance.log.info('Installing controller instrumentation into Delayed::Job')
      include NewRelic::Agent::Instrumentation::ControllerInstrumentation
      if self.instance_methods.include?('name')
        add_transaction_tracer "invoke_job", :category => 'OtherTransaction/DelayedJob', :path => '#{self.name}'
      else
        add_transaction_tracer "invoke_job", :category => 'OtherTransaction/DelayedJob'
      end
    end
  end

  executes do
    Delayed::Job.instance_eval do
      NewRelic::Control.instance.log.info('Attempting to install after_fork hook for Delayed Job')
      if self.respond_to?('after_fork')
        if method_defined?(:after_fork)
          NewRelic::Control.instance.log.info('Delayed::Job.after_fork is defined, aliasing our method and calling the old one')
          def after_fork_with_newrelic
            NewRelic::Agent.after_fork(:force_reconnect => true)
            after_fork_without_newrelic
          end

          alias_method :after_fork_without_newrelic, :after_fork
          alias_method :after_fork, :after_fork_with_newrelic
        else
          NewRelic::Control.instance.log.info('Delayed::Job.after_fork is not defined, defining our after_fork hook')
          def after_fork
            NewRelic::Agent.after_fork(:force_reconnect => true)
            super
          end
        end
      end
    end
  end
end

