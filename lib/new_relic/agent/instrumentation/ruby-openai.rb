# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'ruby-openai/instrumentation'
require_relative 'ruby-openai/chain'
require_relative 'ruby-openai/prepend'

DependencyDetection.defer do
  named :'ruby-openai'

  depends_on do
    # The class that needs to be defined to prepend/chain onto. This can be used
    # to determine whether the library is installed.
    defined?(::OpenAI::Client)
    # Add any additional requirements to verify whether this instrumentation
    # should be installed
  end

  executes do
    ::NewRelic::Agent.logger.info('Installing ruby-openai instrumentation')

    if use_prepend?
      prepend_instrument ::OpenAI::Client,
        NewRelic::Agent::Instrumentation::OpenAI::Client::Prepend,
        NewRelic::Agent::Instrumentation::OpenAI::Client::SUPPORTABILITY_NAME
    else
      chain_instrument NewRelic::Agent::Instrumentation::OpenAI::Client::Chain,
        NewRelic::Agent::Instrumentation::OpenAI::Client::SUPPORTABILITY_NAME
    end
  end
end

