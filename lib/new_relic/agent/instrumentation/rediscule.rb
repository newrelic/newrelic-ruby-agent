require 'new_relic/agent/instrumentation/controller_instrumentation'

DependencyDetection.defer do
  depends_on do
    defined?(::Palmade) && defined?(::Palmade::Rediscule) &&
                           defined?(::Palmade::Rediscule::DaemonPuppet) &&
                           defined?(::Palmade::Rediscule::JanitorPuppet)
  end

  executes do
    NewRelic::Agent.logger.debug 'Installing Rediscule instrumentation'
  end

  executes do
    ::Palmade::Rediscule::DaemonPuppet.class_eval do
      include NewRelic::Agent::Instrumentation::ControllerInstrumentation

      add_transaction_tracer :perform_work, :category =>
        'OtherTransaction/RedisculeJob'
    end
  end

end
