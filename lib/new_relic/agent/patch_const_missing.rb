# This class is for debugging purposes only.
# It inserts instrumentation into class loading to verify
# that no classes are being loaded on the new relic thread,
# which can cause problems in the class loader code.

module ClassLoadingWatcher
  
  extend self
  @@background_thread = nil
  
  def background_thread
    @@background_thread
  end
  
  def set_background_thread(thread)
    @@background_thread = thread
    
    # these tests that check is working...
    #    begin
    #      bad = Bad
    #    rescue
    #    end
    
    #    require 'new_relic/agent/patch_const_missing'
    #    load 'new_relic/agent/patch_const_missing.rb'
  end
  module SanityCheck 
    def new_relic_check_for_badness(*args)
      
      if Thread.current == ClassLoadingWatcher.background_thread    
        msg = "Agent background thread shouldn't be loading classes (#{args.inspect})\n"
        
        exception = NewRelic::Agent::BackgroundLoadingError.new(msg.clone)
        exception.set_backtrace(caller)
        
        NewRelic::Agent.instance.error_collector.notice_error(nil, nil, [], exception)
        msg << caller.join("\n")
        
        NewRelic::Config.instance.log.error msg
      end
    end
  end
  def enable_warning
    Object.class_eval do
      if !defined?(non_new_relic_require)
        alias_method :non_new_relic_require, :require
        alias_method :require, :new_relic_require
      end
      
      if !defined?(non_new_relic_load)
        alias_method :non_new_relic_load, :load
        alias_method :load, :new_relic_load
      end
    end
    Module.class_eval do
      if !defined?(non_new_relic_const_missing)
        alias_method :non_new_relic_const_missing, :const_missing
        alias_method :const_missing, :new_relic_const_missing
      end
    end
  end
  
  def disable_warning
    Object.class_eval do
      if defined?(non_new_relic_require)
        alias_method :require, :non_new_relic_require
        undef non_new_relic_require
      end
      
      if defined?(non_new_relic_load)
        alias_method :load, :non_new_relic_load
        undef non_new_relic_load
      end
    end
    Module.class_eval do
      if defined?(non_new_relic_const_missing)
        alias_method :const_missing, :non_new_relic_const_missing
        undef non_new_relic_const_missing
      end
    end
  end
end

class Object
  include ClassLoadingWatcher::SanityCheck
  
  def new_relic_require(*args)
    new_relic_check_for_badness("Object require", *args)    
    non_new_relic_require(*args)
  end
  
  def new_relic_load(*args)
    new_relic_check_for_badness("Object load", *args)
    non_new_relic_load(*args)
  end
end

class Module
  include ClassLoadingWatcher::SanityCheck
  
  def new_relic_const_missing(*args)
    new_relic_check_for_badness("Module #{self.name} const_missing", *args)
    non_new_relic_const_missing(*args)
  end
end
