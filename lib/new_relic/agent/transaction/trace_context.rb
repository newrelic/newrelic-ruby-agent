# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/trace_context'
require 'new_relic/agent/distributed_trace_payload'

module NewRelic
  module Agent
    class Transaction
      attr_accessor :trace_context_data
      attr_writer   :trace_context_inserted

      module TraceContext
        def insert_trace_context \
            format: NewRelic::Agent::TraceContext::FORMAT_HTTP,
            carrier: nil
          NewRelic::Agent::TraceContext.insert \
            format: format,
            carrier: carrier,
            trace_id: trace_id,
            parent_id: current_segment.guid,
            trace_flags: sampled? ? 0x1 : 0x0,
            trace_state: trace_state
          self.trace_context_inserted = true
        end

        def trace_state
          payload = create_trace_state_payload
          tracestate_entry_key = NewRelic::Agent::TraceContext::AccountHelpers.tracestate_entry_key
          if trace_context_data && !trace_context_data.tracestate.empty?
            "#{tracestate_entry_key}=#{payload.http_safe},#{trace_context_data.tracestate}"
          else
            "#{tracestate_entry_key}=#{payload.http_safe}"
          end
        end

        def create_trace_state_payload
          DistributedTracePayload.for_transaction self
        end

        SUPPORTABILITY_ACCEPT_SUCCESS = "Supportability/TraceContext/AcceptPayload/Success".freeze
        SUPPORTABILITY_ACCEPT_EXCEPTION = "Supportability/TraceContext/AcceptPayload/Exception".freeze

        def accept_trace_context trace_context_data
          return unless Agent.config[:'trace_context.enabled']
          return false if check_trace_context_ignored
          return false unless @trace_context_data = trace_context_data
          return false unless payload = trace_context_data.tracestate_entry

          @trace_id = payload.trace_id
          @parent_transaction_id = payload.transaction_id

          if payload.sampled
            self.sampled = payload.sampled
            self.priority = payload.priority if payload.priority
          end
          NewRelic::Agent.increment_metric SUPPORTABILITY_ACCEPT_SUCCESS
          true
        rescue => e
          NewRelic::Agent.increment_metric SUPPORTABILITY_ACCEPT_EXCEPTION
          NewRelic::Agent.logger.warn "Failed to accept trace context payload", e
          false
        end

        SUPPORTABILITY_MULTIPLE_ACCEPT_TRACE_CONTEXT = "Supportability/TraceContext/AcceptPayload/Ignored/Multiple".freeze
        SUPPORTABILITY_CREATE_BEFORE_ACCEPT_TRACE_CONTEXT = "Supportability/TraceContext/AcceptPayload/Ignored/CreateBeforeAccept".freeze

        def check_trace_context_ignored
          if trace_context_data
            NewRelic::Agent.increment_metric SUPPORTABILITY_MULTIPLE_ACCEPT_TRACE_CONTEXT
            return true
          elsif trace_context_inserted?
            NewRelic::Agent.increment_metric SUPPORTABILITY_CREATE_BEFORE_ACCEPT_TRACE_CONTEXT
            return true
          end
          false
        end
      end

      def trace_context_inserted?
        @trace_context_inserted ||=  false
      end
    end
  end
end
