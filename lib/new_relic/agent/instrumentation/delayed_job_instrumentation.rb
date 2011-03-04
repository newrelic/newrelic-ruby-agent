require 'new_relic/agent/instrumentation/controller_instrumentation'

DependencyDetection.defer do
  depends_on do
    !NewRelic::Control.instance['disable_dj']
  end

  depends_on do
    defined?(::Delayed) && defined?(::Delayed::Job)
  end
  
  executes do
    Delayed::Job.class_eval do
    include NewRelic::Agent::Instrumentation::ControllerInstrumentation
    if self.instance_methods.include?('name')
      add_transaction_tracer "invoke_job", :category => 'OtherTransaction/DelayedJob', :path => '#{self.name}'
    else
      add_transaction_tracer "invoke_job", :category => 'OtherTransaction/DelayedJob'
    end
  end
  end
end

