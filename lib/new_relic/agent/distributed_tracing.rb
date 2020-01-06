# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require_relative 'distributed_tracing/cross_app_payload'
require_relative 'distributed_tracing/cross_app_tracing'

require_relative 'distributed_tracing/distributed_trace_transport_type'
require_relative 'distributed_tracing/distributed_trace_payload'
require_relative 'distributed_tracing/api'

require_relative 'distributed_tracing/trace_context'

module NewRelic
  module Agent
    module DistributedTracing
      extend NewRelic::Agent::DistributedTracing::API
    end
  end
end