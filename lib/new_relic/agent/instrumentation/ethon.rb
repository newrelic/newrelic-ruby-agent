# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'ethon/instrumentation'
require_relative 'ethon/chain'
require_relative 'ethon/prepend'

DependencyDetection.defer do
  named :ethon

  depends_on do
    defined?(Ethon) && Gem::Version.new(Ethon::VERSION) >= Gem::Version.new('0.12.0')
  end

  executes do
    NewRelic::Agent.logger.info('Installing ethon instrumentation')
  end

  executes do
    if use_prepend?
      prepend_instrument Ethon::Easy, NewRelic::Agent::Instrumentation::Ethon::Easy::Prepend
      prepend_instrument Ethon::Multi, NewRelic::Agent::Instrumentation::Ethon::Multi::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::Ethon::Chain
    end
  end
end
