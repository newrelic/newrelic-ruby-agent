# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

DependencyDetection.defer do
  named :logging

  depends_on do
    defined?(Logging::Logger) && NewRelic::Agent.config[:'application_logging.enabled']
  end

  executes do
    require_relative 'logging/instrumentation'

    if use_prepend?
      require_relative 'logging/prepend'
      prepend_instrument Logging::Logger, NewRelic::Agent::Instrumentation::Logging::Logger::Prepend, 'Logging'
    else
      require_relative 'logging/chain'
      chain_instrument NewRelic::Agent::Instrumentation::Logging::Chain, 'Logging'
    end
  end
end
