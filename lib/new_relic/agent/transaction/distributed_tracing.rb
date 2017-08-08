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

        LBRACE = "{".freeze

        # todo: check if browser agent has been injected
        def accept_distributed_trace_payload transport_type, payload
          if inbound_distributed_trace_payload
            NewRelic::Agent.logger.debug "accepted_distributed_trace_payload called, but a payload has already been accepted"
            return false
          elsif self.order > 0
            NewRelic::Agent.logger.warn "create_distributed_trace_payload called before accepted_distributed_trace_payload, ignoring call"
            return false
          end

          payload = if payload.start_with? LBRACE
            DistributedTracePayload.from_json payload
          else
            DistributedTracePayload.from_http_safe payload
          end

          payload.caller_transport_type = transport_type
          self.inbound_distributed_trace_payload = payload
          true
        rescue => e
          NewRelic::Agent.logger.warn "Failed to accept distributed trace payload", e
          false
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

        def parent_ids
          if inbound_distributed_trace_payload && inbound_distributed_trace_payload.parent_ids.last != guid
            inbound_ids = inbound_distributed_trace_payload.parent_ids.dup
            inbound_ids.push guid
            if inbound_ids.size > 3
              inbound_ids.shift
            end
            inbound_ids
          else
            [guid]
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
