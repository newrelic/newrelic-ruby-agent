# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'logging/instrumentation'
require_relative 'logging/chain'
require_relative 'logging/prepend'

DependencyDetection.defer do
  named :logging

  depends_on do
    defined?(Logging::Logger) && NewRelic::Agent.config[:'application_logging.enabled']
  end

  executes do
    if use_prepend?
      prepend_instrument Logging::Logger, NewRelic::Agent::Instrumentation::Logging::Logger::Prepend, 'Logging'
    else
      chain_instrument NewRelic::Agent::Instrumentation::Logging::Chain, 'Logging'
    end
  end
end
