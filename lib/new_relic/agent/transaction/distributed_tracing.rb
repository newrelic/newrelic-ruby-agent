# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/distributed_trace_payload'

module NewRelic
  module Agent
    class Transaction
      module DistributedTracing
        attr_accessor :distributed_trace_payload

        def distributed_trace?
          !!distributed_trace_payload
        end

        def create_distributed_trace_payload
          return unless Agent.config[:'distributed_tracing.enabled']
          self.distributed_trace_payload_created = true
          DistributedTracePayload.for_transaction self
        end

        LBRACE = "{".freeze

        def accept_distributed_trace_payload transport_type, payload
          return unless Agent.config[:'distributed_tracing.enabled']
          if distributed_trace_payload
            NewRelic::Agent.increment_metric "Supportability/DistributedTracing/AcceptFailure/PayloadAlreadyAccepted"
            return false
          elsif distributed_trace_payload_created?
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
          self.distributed_trace_payload = payload

          self.sampled = payload.sampled unless payload.sampled.nil?

          true
        rescue => e
          NewRelic::Agent.increment_metric "Supportability/DistributedTracing/AcceptFailure/Unknown"
          NewRelic::Agent.logger.warn "Failed to accept distributed trace payload", e
          false
        end

        def distributed_trace_trip_id
          if distributed_trace_payload
            distributed_trace_payload.trip_id
          else
            guid
          end
        end

        def parent_id
          # The payload comes from our parent transaction, so its ID
          # is our parent ID.
          #
          distributed_trace_payload && distributed_trace_payload.id
        end

        def grandparent_id
          # The payload comes from our parent transaction, so its
          # parent ID is our grandparent ID.
          #
          distributed_trace_payload && distributed_trace_payload.parent_id
        end

        def distributed_trace_payload_created?
          @distributed_trace_payload_created ||=  false
        end

        attr_writer :distributed_trace_payload_created

        def append_distributed_trace_info transaction_payload
          return unless Agent.config[:'distributed_tracing.enabled']
          if distributed_trace_payload
            distributed_trace_payload.assign_intrinsics self, transaction_payload
          elsif distributed_trace_payload_created?
            DistributedTracePayload.assign_intrinsics_for_first_trace self, transaction_payload
          end
        end

        def assign_distributed_trace_intrinsics
          return unless Agent.config[:'distributed_tracing.enabled']
          DistributedTracePayload::INTRINSIC_KEYS.each do |key|
            next unless value = @payload[key]
            attributes.add_intrinsic_attribute key, value
          end
          nil
        end

        # This method returns transport_duration in seconds. Transport duration
        # is stored in milliseconds on the payload, but it's needed in seconds
        # for metrics and intrinsics.
        def transport_duration
          return unless distributed_trace_payload
          (start_time.to_f * 1000 - distributed_trace_payload.timestamp) / 1000
        end
      end
    end
  end
end
