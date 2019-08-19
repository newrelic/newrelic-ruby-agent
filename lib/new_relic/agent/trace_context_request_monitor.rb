# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/distributed_trace_transport_type'
require 'new_relic/agent/inbound_request_monitor'
require 'new_relic/agent/trace_context'

module NewRelic
  module Agent
    class TraceContextRequestMonitor < InboundRequestMonitor

      SUPPORTABILITY_PARSE_EXCEPTION = "Supportability/TraceContext/Parse/Exception".freeze
      TRACEPARENT                    = 'HTTP_TRACEPARENT'.freeze

      def on_finished_configuring(events)
        return unless NewRelic::Agent.config[:'trace_context.enabled']
        events.subscribe(:before_call, &method(:on_before_call))
      end

      def on_before_call(request)
        return unless NewRelic::Agent.config[:'trace_context.enabled'] && request[TRACEPARENT]
        trace_context = TraceContext.parse(
          format: TraceContext::FORMAT_RACK,
          carrier: request,
          trace_state_entry_key: TraceContext::AccountHelpers.trace_state_entry_key,
          caller_transport_type: DistributedTraceTransportType.for_rack_request(request)
        )
        if trace_context.nil?
          NewRelic::Agent.increment_metric SUPPORTABILITY_PARSE_EXCEPTION
          return
        end

        return unless txn = Tracer.current_transaction

        if txn.accept_trace_context trace_context
          txn.trace_state_payload.caller_transport_type = DistributedTraceTransportType.for_rack_request(request)
        end
      end
    end
  end
end
