# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'ruby_openai/instrumentation'
require_relative 'ruby_openai/chain'
require_relative 'ruby_openai/prepend'

DependencyDetection.defer do
  named :'ruby_openai'

  depends_on do
    NewRelic::Agent.config[:'ai_monitoring.enabled'] &&
      defined?(OpenAI) && defined?(OpenAI::Client) &&
      NewRelic::Helper.version_satisfied?(OpenAI::VERSION, '>=', '3.4.0')
  end

  executes do
    if use_prepend?
      # TODO: Remove condition when we drop support for versions below 5.0.0
      if NewRelic::Helper.version_satisfied?(OpenAI::VERSION, '>=', '5.0.0')
        prepend_instrument OpenAI::Client,
          NewRelic::Agent::Instrumentation::OpenAI::Prepend,
          NewRelic::Agent::Instrumentation::OpenAI::VENDOR
      else
        prepend_instrument OpenAI::Client.singleton_class,
          NewRelic::Agent::Instrumentation::OpenAI::Prepend,
          NewRelic::Agent::Instrumentation::OpenAI::VENDOR
      end
    else
      chain_instrument NewRelic::Agent::Instrumentation::OpenAI::Chain,
        NewRelic::Agent::Instrumentation::OpenAI::VENDOR
    end
  end
end
