# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/inbound_request_monitor'
require 'new_relic/agent/cross_app_tracing'

module NewRelic
  module Agent
    class DistributedTraceMonitor < InboundRequestMonitor
      NEWRELIC_TRACE_KEY_ACCEPTED_FORMATS = ['newrelic'.freeze, 'NEWRELIC'.freeze, 'Newrelic'.freeze]
      HTTP_TRANSPORT_TYPE = 'HTTP'.freeze

      def on_finished_configuring(events)
        return unless NewRelic::Agent.config[:'distributed_tracing.enabled']
        events.subscribe(:before_call, &method(:on_before_call))
      end

      def on_before_call(request)
        return unless NewRelic::Agent.config[:'distributed_tracing.enabled']
        return unless newrelic_trace_key = (request.keys & NEWRELIC_TRACE_KEY_ACCEPTED_FORMATS).first
        return unless payload = request[newrelic_trace_key]

        state = NewRelic::Agent::TransactionState.tl_get
        txn = state.current_transaction
        if txn.accept_distributed_trace_payload payload
          txn.distributed_trace_payload.caller_transport_type = HTTP_TRANSPORT_TYPE
        end
      end
    end
  end
end
