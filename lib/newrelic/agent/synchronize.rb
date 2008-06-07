
require 'sync'


module NewRelic::Agent::Synchronize
  
  def synchronize_sync(&block)
    @_local_sync ||= Sync.new
    
    @_local_sync.synchronize(:EX) do
      block.call
    end
  end
  
  
  def synchronize_thread
    old_val = Thread.critical
    
    Thread.critical = true
    
    begin
      yield
    ensure
      Thread.critical = old_val
    end
  end
  
  alias synchronize synchronize_sync
  alias synchronize_quick synchronize_sync
  alias synchronized_long synchronize_sync
   
end
