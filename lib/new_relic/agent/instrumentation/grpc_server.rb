# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative 'grpc/server/chain'
require_relative 'grpc/server/prepend'

DependencyDetection.defer do
  named :grpc_server

  depends_on do
    defined?(::GRPC) && defined?(::GRPC::RpcServer)
  end

  executes do
    if use_prepend?
      prepend_instrument ::GRPC::RpcServer, ::NewRelic::Agent::Instrumentation::GRPC::Server::Prepend
    else
      chain_instrument ::NewRelic::Agent::Instrumentation::GRPC::Server::Chain
    end
  end
end
