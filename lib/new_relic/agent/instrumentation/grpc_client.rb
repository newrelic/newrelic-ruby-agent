# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative 'grpc/client/chain'
require_relative 'grpc/client/prepend'

DependencyDetection.defer do
  named :grpc_client

  depends_on do
    defined?(::GRPC) && defined?(::GRPC::ClientStub)
  end

  executes do
    if use_prepend?
      prepend_instrument ::GRPC::ClientStub, ::NewRelic::Agent::Instrumentation::GRPC::Client::Prepend
    else
      chain_instrument ::NewRelic::Agent::Instrumentation::GRPC::Client::Chain
    end
  end
end
