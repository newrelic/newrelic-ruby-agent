if defined?(PhusionPassenger)
  NewRelic::Agent.logger.debug "Installing Passenger event hooks."

  PhusionPassenger.on_event(:stopping_worker_process) do 
    NewRelic::Agent.logger.debug "Passenger stopping this process, shutdown the agent."
    NewRelic::Agent.instance.shutdown
  end

  PhusionPassenger.on_event(:starting_worker_process) do |forked|
    if forked 
      # We want to reset the stats from the stats engine in case any carried
      # over into the spawned process.  Don't clear them in case any were
      # cached.
      NewRelic::Agent.after_fork(:force_reconnect => true)
    else 
      # We're in conservative spawning mode. We don't need to do anything.
    end
  end
  
end 