# This class is for debugging purposes only.
#
class Module
  @@newrelic_agent_thread = nil
  def new_relic_const_missing(*args)
    if Thread.current == @@newrelic_agent_thread
      msg = "Agent background thread shouldn't be calling const_missing (#{args.inspect})   \n"
      msg << caller[0..4].join("   \n")
      NewRelic::Config.instance.log.warn msg 
    end
    original_const_missing(*args)
  end
  
  def newrelic_enable_warning
    Module.class_eval do
      if !defined?(original_const_missing)
        alias_method :original_const_missing, :const_missing
        alias_method :const_missing, :new_relic_const_missing
      end
    end
  end
  def newrelic_disable_warning
    Module.class_eval do
      alias_method :const_missing, :original_const_missing if defined?(original_const_missing)
    end
  end
  
  def newrelic_set_agent_thread(thread)
    @@newrelic_agent_thread = thread
  end
end
