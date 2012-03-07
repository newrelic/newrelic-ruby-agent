require 'new_relic/agent/instrumentation/controller_instrumentation'

module NewRelic::Agent::Instrumentation
  module Camping
    def self.attach(mod)
      NewRelic::Agent.logger.debug "Installing Camping hook to #{mod.name}"

      mod::Base.module_eval do
        include NewRelic::Agent::Instrumentation::ControllerInstrumentation

        add_transaction_tracer :service
      end
    end

  end
end
