# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'httpx/chain'
require_relative 'httpx/instrumentation'
require_relative 'httpx/prepend'

DependencyDetection.defer do
  named :httpx

  depends_on do
    defined?(HTTPX) && NewRelic::Helper.version_satisfied?(HTTPX::VERSION, '>=', '1.0.0')
  end

  executes do
    if use_prepend?
      prepend_instrument HTTPX::Session, NewRelic::Agent::Instrumentation::HTTPX::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::HTTPX::Chain
    end
  end
end
