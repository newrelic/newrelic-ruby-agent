# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'bedrock/instrumentation'
require_relative 'bedrock/chain'
require_relative 'bedrock/prepend'

DependencyDetection.defer do
  named :bedrock

  depends_on do
    defined?(Aws::BedrockRuntime::Client) && NewRelic::Agent.config[:'ai_monitoring.enabled'] != false
  end

  executes do
    NewRelic::Agent.logger.info('Installing bedrock instrumentation')

    if use_prepend?
      prepend_instrument Aws::BedrockRuntime::Client, NewRelic::Agent::Instrumentation::Bedrock::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::Bedrock::Chain
    end
  end
end
