if defined?(Palmade::PuppetMaster::ThinPuppet)
  Palmade::PuppetMaster::ThinPuppet.class_eval do
    NewRelic::Agent.logger.debug "Installing Puppet Master worker hook."
    old_worker_loop = instance_method(:work_loop)
    define_method(:work_loop) do | *args |
      NewRelic::Agent.after_fork(:force_reconnect => true)
      old_worker_loop.bind(self).call(*args)
    end
  end
end
