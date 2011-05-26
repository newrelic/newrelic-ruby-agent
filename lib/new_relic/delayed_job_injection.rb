require 'dependency_detection'
# This installs some code to manually start the agent when a delayed
# job worker starts.  It's not really instrumentation.  It's more like
# a hook from DJ to the Ruby Agent so it gets loaded at the time the
# Ruby Agent initializes, which must be before the DJ worker
# initializes.  Loaded from control.rb
module NewRelic
  module DelayedJobInjection
    extend self
    attr_accessor :worker_name
  end
end

DependencyDetection.defer do
  depends_on do
    NewRelic::Control.instance.log.info("Attempting to install Delayed Job initialization hook")
    value = defined?(::Delayed) && defined?(::Delayed::Worker)
    NewRelic::Control.instance.log.info("Delayed Job and Delayed Worker instrumentation #{value ? 'is' : 'is not'} being installed")
  end

  executes do
    Delayed::Worker.class_eval do
      def initialize_with_new_relic(*args)
        NewRelic::Control.instance.log.info("Initializing Delayed Job with New Relic")
        value = initialize_without_new_relic(*args)
        NewRelic::Control.instance.log.info("Beginning New Relic Delayed Job initialization")
        worker_name = case
                      when self.respond_to?(:name) then self.name
                      when self.class.respond_to?(:default_name) then self.class.default_name
                      end
        dispatcher_instance_id = worker_name || "host:#{Socket.gethostname} pid:#{Process.pid}" rescue "pid:#{Process.pid}"
        log_message = "New Relic Monitoring DJ worker #{dispatcher_instance_id}"
        NewRelic::Control.instance.log.info(log_message)
        say log_message
        NewRelic::DelayedJobInjection.worker_name = worker_name
        NewRelic::Control.instance.init_plugin :dispatcher => :delayed_job, :dispatcher_instance_id => dispatcher_instance_id
      end
      
      NewRelic::Control.instance.log.debug("Aliasing initialize method to hook our instrumentation into Delayed::Worker#initialize")
      alias initialize_without_new_relic initialize
      alias initialize initialize_with_new_relic
    end
  end
end
DependencyDetection.detect!
