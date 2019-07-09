# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/inbound_request_monitor'
require 'new_relic/agent/trace_context'

module NewRelic
  module Agent
    class TraceContextRequestMonitor < InboundRequestMonitor
      def on_finished_configuring(events)
        return unless NewRelic::Agent.config[:'trace_context.enabled']
        events.subscribe(:before_call, &method(:on_before_call))
      end


      def on_before_call(request)
        return unless NewRelic::Agent.config[:'trace_context.enabled']
        return unless trace_context = TraceContext.parse(
          format: TraceContext::RackFormat,
          carrier: request,
          tracestate_entry_key: "nr"
        )
        return unless txn = Tracer.current_transaction

        txn.accept_trace_context trace_context
      end
    end
  end
end
