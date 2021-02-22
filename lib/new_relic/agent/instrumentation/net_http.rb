# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative 'net_http/chain'
require_relative 'net_http/prepend'

DependencyDetection.defer do
  named :net_http

  depends_on do
    defined?(Net) && defined?(Net::HTTP)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Net:HTTP Wrappers'
    require 'new_relic/agent/http_clients/net_http_wrappers'
  end

  conflicts_with_prepend do
    defined?(::Airbrake)
  end

  conflicts_with_prepend do
    defined?(::Rack::MiniProfiler)
  end

  conflicts_with_prepend do
    source_location_for(Net::HTTP, "request") =~ /airbrake|profiler/i
  end

  executes do
    if use_prepend?
      prepend_instrument ::Net::HTTP, ::NewRelic::Agent::Instrumentation::NetHTTP::Prepend
    else 
      chain_instrument ::NewRelic::Agent::Instrumentation::NetHTTP::Chain
    end
  end
end
