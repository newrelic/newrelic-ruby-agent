require 'new_relic/agent/instrumentation/controller_instrumentation'

module NewRelic::Agent::Instrumentation::DelayedJobInstrumentation

  Delayed::Job.class_eval do
    include NewRelic::Agent::Instrumentation::ControllerInstrumentation
    if self.instance_methods.include?('name')
      add_transaction_tracer "invoke_job", :category => 'OtherTransaction/DelayedJob', :path => '#{self.name}'
    else
      add_transaction_tracer "invoke_job", :category => 'OtherTransaction/DelayedJob'
    end
  end
  
end if defined?(Delayed::Job)
