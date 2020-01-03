# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require_relative 'distributed_trace_transport_type'
require 'new_relic/agent/inbound_request_monitor'
require_relative 'trace_context'

module NewRelic
  module Agent
    class TraceContextRequestMonitor < InboundRequestMonitor
      TRACEPARENT = 'HTTP_TRACEPARENT'.freeze

      def on_finished_configuring(events)
        return unless enabled?
        events.subscribe(:before_call, &method(:on_before_call))
      end

      def on_before_call(request)
        return unless enabled? && request[TRACEPARENT]
        trace_context = TraceContext.parse(
          format: TraceContext::FORMAT_RACK,
          carrier: request,
          trace_state_entry_key: TraceContext::AccountHelpers.trace_state_entry_key,
        )
        return if trace_context.nil?

        return unless txn = Tracer.current_transaction

        if txn.accept_trace_context trace_context
          txn.trace_state_payload.caller_transport_type = DistributedTraceTransportType.for_rack_request(request)
        end
      end

      W3C_FORMAT = "w3c".freeze

      def enabled?
        NewRelic::Agent.config[:'distributed_tracing.enabled'] && (NewRelic::Agent.config[:'distributed_tracing.format'] == W3C_FORMAT)
      end
    end
  end
end
