# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'logstasher/instrumentation'
require_relative 'logstasher/chain'
require_relative 'logstasher/prepend'

DependencyDetection.defer do
  named :logstasher

  depends_on do
    defined?(LogStasher) &&
      NewRelic::Agent.config[:'application_logging.enabled']
  end

  executes do
    NewRelic::Agent.logger.info('Installing LogStasher instrumentation')

    if use_prepend?
      prepend_instrument LogStasher, NewRelic::Agent::Instrumentation::LogStasher::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::LogStasher::Chain
    end
  end
end
