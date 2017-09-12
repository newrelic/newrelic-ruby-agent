# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/distributed_trace_payload'

module NewRelic
  module Agent
    class Transaction
      module DistributedTracing

        def create_distributed_trace_payload url = nil
          return unless Agent.config[:'distributed_tracing.enabled']
          self.order += 1
          DistributedTracePayload.for_transaction self, url
        end

        LBRACE = "{".freeze

        def accept_distributed_trace_payload transport_type, payload
          return unless Agent.config[:'distributed_tracing.enabled']
          if inbound_distributed_trace_payload
            NewRelic::Agent.increment_metric "Supportability/DistributedTracing/AcceptFailure/PayloadAlreadyAccepted"
            return false
          elsif self.order > 0
            NewRelic::Agent.increment_metric "Supportability/DistributedTracing/AcceptFailure/CreateDistributedTracePayload-before-AcceptDistributedTracePayload"
            return false
          elsif name_frozen?
            NewRelic::Agent.increment_metric "Supportability/DistributedTracing/AcceptFailure/BrowserAgentInjected"
            return false
          end

          payload = if payload.start_with? LBRACE
            DistributedTracePayload.from_json payload
          else
            DistributedTracePayload.from_http_safe payload
          end

          payload.caller_transport_type = transport_type
          self.inbound_distributed_trace_payload = payload

          self.sampled = payload.sampled unless payload.sampled.nil?

          true
        rescue => e
          NewRelic::Agent.increment_metric "Supportability/DistributedTracing/AcceptFailure/Unknown"
          NewRelic::Agent.logger.warn "Failed to accept distributed trace payload", e
          false
        end

        def inbound_distributed_trace_payload
          @inbound_distributed_trace_payload ||= nil
        end

        def distributed_trace?
          !!inbound_distributed_trace_payload
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
          if inbound_distributed_trace_payload &&
               inbound_distributed_trace_payload.parent_ids &&
               inbound_distributed_trace_payload.parent_ids.last != guid
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
            inbound_distributed_trace_payload.depth
          else
            1
          end
        end

        def order
          @order ||= 0
        end

        attr_writer :order

        def append_distributed_tracing_info payload
          return unless Agent.config[:'distributed_tracing.enabled']
          if inbound_distributed_trace_payload
            inbound_distributed_trace_payload.assign_intrinsics self, payload
          elsif order > 0
            DistributedTracePayload.assign_initial_intrinsics self, payload
          end
        end

        def assign_distributed_tracing_intrinsics
          return unless Agent.config[:'distributed_tracing.enabled']
          DistributedTracePayload::INTRINSIC_KEYS.each do |key|
            next unless value = @payload[key]
            attributes.add_intrinsic_attribute key, value
          end
          nil
        end

        # This method returns transport_duration in seconds. Transport duration
        # is stored in milliseconds on the payload, but it needed in seconds for
        # metrics and intrinsics.
        def transport_duration
          return unless inbound_distributed_trace_payload
          (start_time.to_f * 1000 - inbound_distributed_trace_payload.timestamp) / 1000
        end
      end
    end
  end
end
