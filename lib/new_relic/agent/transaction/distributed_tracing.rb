# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/distributed_trace_payload'

module NewRelic
  module Agent
    class Transaction
      module DistributedTracing

        def create_distributed_trace_payload url = nil
          self.order += 1
          DistributedTracePayload.for_transaction self, url
        end

        # todo: what do we do with transport type?
        # todo: check if browser agent has been injected
        def accept_distributed_trace_payload transport_type, payload_json
          if inbound_distributed_trace_payload
            NewRelic::Agent.logger.debug "accepted_distributed_trace_payload called, but a payload has already been accepted"
            return
          elsif self.order > 0
            NewRelic::Agent.logger.warn "create_distributed_trace_payload called before accepted_distributed_trace_payload, ignoring call"
            return
          end
          self.inbound_distributed_trace_payload = DistributedTracePayload.from_json payload_json
        end

        def inbound_distributed_trace_payload
          @inbound_distributed_trace_payload ||= nil
        end

        attr_writer :inbound_distributed_trace_payload

        def distributed_tracing_trip_id
          if inbound_distributed_trace_payload
            inbound_distributed_trace_payload.trip_id
          else
            guid
          end
        end

        def depth
          if inbound_distributed_trace_payload
            inbound_distributed_trace_payload.depth + 1
          else
            1
          end
        end

        def order
          @order ||= 0
        end

        attr_writer :order

        def append_distributed_tracing_info(payload)
          if inbound_distributed_trace_payload
            inbound_distributed_trace_payload.assign_intrinsics payload
            payload[:guid] = guid
          end
        end
      end
    end
  end
end
