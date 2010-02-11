# This installs some code to manually start the agent when a delayed job worker starts.

Delayed::Worker.class_eval do
  def initialize_with_new_relic(*args)
    initialize_without_new_relic(*args)
    dispatcher_instance_id = case
    when self.respond_to?(:name) then self.name
    when self.class.respond_to?(:default_name) then self.class.default_name
    else
      "host:#{Socket.gethostname} pid:#{Process.pid}" rescue "pid:#{Process.pid}"
    end
    
    NewRelic::Agent.manual_start :dispatcher => :delayed_job, :dispatcher_instance_id => dispatcher_instance_id
  end
  
  alias initialize_without_new_relic initialize
  alias initialize initialize_with_new_relic
end if defined?(Delayed::Worker) and not NewRelic::Control.instance['disable_dj']
