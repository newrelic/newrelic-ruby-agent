# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'ruby_openai/instrumentation'
require_relative 'ruby_openai/chain'
require_relative 'ruby_openai/prepend'

DependencyDetection.defer do
  named :'ruby_openai'

  OPENAI_VERSION = Gem::Version.new(OpenAI::VERSION) if defined?(OpenAI)
  VERSION_5_0_0 = Gem::Version.new('5.0.0')

  depends_on do
    defined?(OpenAI) && defined?(OpenAI::Client) && # clear for 3.4.0
      OPENAI_VERSION >= Gem::Version.new('3.4.0')
    # maybe add DT check here eventually?
    # possibly also a config check for ai.enabled
  end

  executes do
    NewRelic::Agent.logger.info('Installing ruby-openai instrumentation')
    if use_prepend?
      if OPENAI_VERSION >= VERSION_5_0_0
        prepend_instrument OpenAI::Client,
          NewRelic::Agent::Instrumentation::OpenAI::Prepend,
          NewRelic::Agent::Instrumentation::OpenAI::VENDOR
      elsif OPENAI_VERSION < VERSION_5_0_0
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
