if defined?(PhusionPassenger)
  NewRelic::Control.instance.log.debug "Installing Passenger shutdown hook."
  PhusionPassenger.on_event(:stopping_worker_process) do 
    NewRelic::Control.instance.log.info "Passenger stopping this process, shutdown the agent."
    NewRelic::Agent.instance.shutdown
  end
end 