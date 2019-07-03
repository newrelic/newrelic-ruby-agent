# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/trace_context'
require 'new_relic/agent/distributed_trace_payload'

module NewRelic
  module Agent
    class Transaction
      attr_accessor :trace_context

      module TraceContext
        def insert_trace_context \
            format: NewRelic::Agent::TraceContext::HttpFormat,
            carrier: nil
          NewRelic::Agent::TraceContext.insert \
            format: format,
            carrier: carrier,
            trace_id: trace_id,
            parent_id: current_segment.guid,
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

        def accept_trace_context trace_context
          return unless Agent.config[:'trace_context.enabled']
          return unless @trace_context = trace_context
          return unless payload = trace_context.tracestate_entry
          return unless check_trusted_account payload

          @trace_id = payload.trace_id
          @parent_transaction_id = payload.transaction_id

          if payload.sampled
            self.sampled = payload.sampled
            self.priority = payload.priority if payload.priority
          end
        end
      end
    end
  end
end
