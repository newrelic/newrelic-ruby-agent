# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'mohair/instrumentation'
require_relative 'mohair/chain'
require_relative 'mohair/prepend'

DependencyDetection.defer do
  named :fiber

  depends_on do
    defined?(Fiber)
  end

  executes do
    if use_prepend?
      prepend_instrument Fiber, NewRelic::Agent::Instrumentation::Mohair::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::Mohair::Chain
    end
  end
end
