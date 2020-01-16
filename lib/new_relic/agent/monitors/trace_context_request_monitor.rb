# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module DistributedTracing
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

          if txn.distributed_tracer.accept_trace_context trace_context
            transport_type = DistributedTraceTransportType.for_rack_request(request)
            txn.distributed_tracer.trace_state_payload.caller_transport_type = transport_type
          end
        end

        W3C_FORMAT = "w3c".freeze

        def enabled?
          Agent.config[:'distributed_tracing.enabled'] && 
          (Agent.config[:'distributed_tracing.format'] == W3C_FORMAT)
        end
      end
    end
  end
end