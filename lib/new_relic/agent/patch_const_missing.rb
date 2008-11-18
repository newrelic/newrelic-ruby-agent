# This class is for debugging purposes only.
#
class Class
    
  def new_relic_const_missing(*args)
    if Thread.current == @agent_thread
      STDERR.puts "Agent background thread shouldn't be calling const_missing!!!"
      STDERR.puts caller.join("\n")
      exit -1
    end
    
    original_const_missing(*args)
  end
  
  alias_method :original_const_missing, :const_missing
  alias_method :const_missing, :new_relic_const_missing
  
  def new_relic_set_agent_thread(thread)
    @agent_thread = thread
  end
end
