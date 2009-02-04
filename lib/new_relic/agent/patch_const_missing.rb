# This class is for debugging purposes only.
#

public

def newrelic_set_agent_thread(thread)
  @@newrelic_agent_thread = thread
  
# these tests that check is working...
#    begin
#      bad = Bad
#    rescue
#    end

#    require 'new_relic/agent/patch_const_missing'
#    load 'new_relic/agent/patch_const_missing.rb'
end


def new_relic_check_for_badness(*args)
  
  @@newrelic_agent_thread ||= nil
  
  if Thread.current == @@newrelic_agent_thread    
    msg = "Agent background thread shouldn't be loading classes (#{args.inspect})\n"

    exception = NewRelic::Agent::BackgroundLoadingError.new(msg.clone)
    exception.set_backtrace(caller)
    
    NewRelic::Agent.instance.error_collector.notice_error(exception, nil)
    
    msg << caller.join("\n")
    
    NewRelic::Config.instance.log.error msg
  end
end


def newrelic_enable_warning
  Object.newrelic_enable_warning_object
  Module.newrelic_enable_warning_module
end


def newrelic_disable_warning
  Object.newrelic_disable_warning_object
  Module.newrelic_disable_warning_module
end



class Object
  
  def new_relic_require(*args)
    new_relic_check_for_badness("Object require", *args)    
    non_new_relic_require(*args)
  end
  
  
  def new_relic_load(*args)
    new_relic_check_for_badness("Object load", *args)
    non_new_relic_load(*args)
  end
  
  
  def newrelic_enable_warning_object
    Object.class_eval do
      if !defined?(Object.non_new_relic_require)
        alias_method :non_new_relic_require, :require
        alias_method :require, :new_relic_require
      end
      
      if !defined?(Object.non_new_relic_load)
        alias_method :non_new_relic_load, :load
        alias_method :load, :new_relic_load
      end
    end
  end

  def newrelic_disable_warning_object
    Object.class_eval do
      if defined?(Object.non_new_relic_require)
        alias_method :require, :non_new_relic_require
        undef non_new_relic_require
      end
      
      if defined?(Object.non_new_relic_load)
        alias_method :load, :non_new_relic_load
        undef non_new_relic_load
      end
    end
  end
  
end



class Module

  def new_relic_const_missing(*args)
    new_relic_check_for_badness("Module #{self.name} const_missing", *args)
    non_new_relic_const_missing(*args)
  end
  
  def newrelic_enable_warning_module
    Module.class_eval do
      if !defined?(Module.non_new_relic_const_missing)
        alias_method :non_new_relic_const_missing, :const_missing
        alias_method :const_missing, :new_relic_const_missing
      end
    end
  end
  
  def newrelic_disable_warning_module
    Module.class_eval do
      if defined?(Module.non_new_relic_const_missing)
        alias_method :const_missing, :non_new_relic_const_missing
        undef non_new_relic_const_missing
      end
    end
  end
  
end

