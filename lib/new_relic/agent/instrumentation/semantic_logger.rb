# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

DependencyDetection.defer do
  named :semantic_logger

  depends_on do
    defined?(SemanticLogger::Appenders) && NewRelic::Agent.config[:'application_logging.enabled'] && NewRelic::Agent.config[:'instrumentation.semantic_logger'] != 'disabled'
  end

  executes do
    require_relative 'semantic_logger/instrumentation'

    if use_prepend?
      require_relative 'semantic_logger/prepend'
      prepend_instrument SemanticLogger::Appenders, NewRelic::Agent::Instrumentation::SemanticLogger::Appenders::Prepend, 'SemanticLogger'
    else
      require_relative 'semantic_logger/chain'
      chain_instrument NewRelic::Agent::Instrumentation::SemanticLogger::Appenders::Chain, 'SemanticLogger'
    end
  end
end
