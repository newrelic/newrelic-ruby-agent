# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/distributed_trace_payload'

module NewRelic
  module Agent
    class Transaction
      module DistributedTracing

        def create_distributed_trace_payload url = nil
          @order += 1
          DistributedTracingPayload.for_transaction self, url
        end

        def distributed_tracing_trip_id
          guid
        end

        def depth
          @depth ||= 1
        end

        def order
          @order ||= 1
        end
      end
    end
  end
end
