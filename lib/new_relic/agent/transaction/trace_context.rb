# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/trace_context'
require 'new_relic/agent/distributed_trace_payload'

module NewRelic
  module Agent
    class Transaction
      module TraceContext
        def insert_trace_context carrier: nil
          NewRelic::Agent::TraceContext.insert \
            carrier: carrier,
            trace_id: trace_id,
            parent_id: parent_id,
            trace_flags: sampled? ? 0x1 : 0x0,
            trace_state: trace_state
        end

        def trace_state
          entry = create_trace_state_entry
          "nr=#{entry.http_safe}"
        end

        def create_trace_state_entry
          DistributedTracePayload.for_transaction self
        end
      end
    end
  end
end
