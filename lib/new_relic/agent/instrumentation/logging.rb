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

    # prepend_instrument and chain_instrument call extract_supportability_name
    # to get the library name for supportability metrics and info-level logging.
    # This is done by spliting on the 2nd to last spot of the instrumented
    # module. If this isn't how we want the name to appear, pass in the desired
    # name as a third argument.
    if use_prepend?
      require_relative 'logging/prepend'
      prepend_instrument Logging::Logger, NewRelic::Agent::Instrumentation::Logging::Logger::Prepend
    else
      require_relative 'logging/chain'
      chain_instrument NewRelic::Agent::Instrumentation::Logging::Chain
    end
  end
end
