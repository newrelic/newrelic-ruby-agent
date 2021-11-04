# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative 'tilt/instrumentation'
require_relative 'tilt/chain'
require_relative 'tilt/prepend'

DependencyDetection.defer do
  named :tilt

  # prior to 0.8.0, the prepare method was known as compile
  depends_on { defined?(::Tilt) && ::Tilt::VERSION >= '0.8.0' }

  executes do
    ::NewRelic::Agent.logger.info  "Installing Tilt instrumentation"
  end

  executes do
    if use_prepend?
      prepend_instrument ::Tilt::Template, NewRelic::Agent::Instrumentation::Tilt::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::Tilt
    end
  end
end
