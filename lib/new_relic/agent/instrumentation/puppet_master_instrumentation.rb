DependencyDetection.defer do
  depends_on do
    defined?(::Palmade) && defined?(::Palmade::PuppetMaster) &&
      defined?(::Palmade::PuppetMaster::Puppets) &&
      defined?(::Palmade::PuppetMaster::Puppets::Base)
  end

  executes do
    NewRelic::Agent.logger.debug 'Installing Puppet Master instrumentation'
  end

  executes do
    Palmade::PuppetMaster::Puppets::Base.class_eval do
      NewRelic::Agent.logger.debug "Installing Puppet Master puppet hook."
      old_after_fork = instance_method(:after_fork)
      define_method(:after_fork) do |worker|
        NewRelic::Agent.after_fork(:force_reconnect => true)
        old_after_fork.bind(self).call(worker)
      end
    end
  end
end
