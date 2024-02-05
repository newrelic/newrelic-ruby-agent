# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'ruby_openai/instrumentation'
require_relative 'ruby_openai/chain'
require_relative 'ruby_openai/prepend'

DependencyDetection.defer do
  named :'ruby_openai'

  depends_on do
    defined?(OpenAI) && defined?(OpenAI::Client)
    # maybe add DT check here eventually?
    # possibly also a config check for ai.enabled
  end

  executes do
    NewRelic::Agent.logger.info('Installing ruby-openai instrumentation')

    if use_prepend?
      # instead of metaprogramming on OpenAI::Client, we could also use
      # OpenAI::HTTP, it's a module that's required by OpenAI::Client and
      # contains the json_post method we're instrumenting
      prepend_instrument OpenAI::Client,
        NewRelic::Agent::Instrumentation::OpenAI::Prepend,
        NewRelic::Agent::Instrumentation::OpenAI::VENDOR
    else
      chain_instrument NewRelic::Agent::Instrumentation::OpenAI::Chain,
        NewRelic::Agent::Instrumentation::OpenAI::VENDOR
    end
  end
end
