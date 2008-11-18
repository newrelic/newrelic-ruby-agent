# This class is for debugging purposes only.
#
class Class
    
  def new_relic_const_missing(*args)
    raise "Agent background thread shouldn't be calling const_missing!!!" if Thread.current == @agent_thread
    original_const_missing(*args)
  end
  
  alias_method :original_const_missing, :const_missing
  alias_method :const_missing, :new_relic_const_missing
  
  def new_relic_set_agent_thread(thread)
    @agent_thread = thread
  end
end
