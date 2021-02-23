# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative 'http/chain'
require_relative 'http/prepend'

DependencyDetection.defer do
  named :httprb

  depends_on do
    defined?(HTTP) && defined?(HTTP::Client)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing http.rb instrumentation'
    require 'new_relic/agent/distributed_tracing/cross_app_tracing'
    require 'new_relic/agent/http_clients/http_rb_wrappers'
  end

  executes do
    if use_prepend?
      prepend_instrument HTTP::Client, ::NewRelic::Agent::Instrumentation::HTTP::Prepend
    else
      chain_instrument ::NewRelic::Agent::Instrumentation::HTTP::Chain
    end
  end
end
