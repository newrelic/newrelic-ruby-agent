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

        SUPPORTABILITY_CREATE_PAYLOAD_SUCCESS   = "Supportability/DistributedTrace/CreatePayload/Success".freeze
        SUPPORTABILITY_CREATE_PAYLOAD_EXCEPTION = "Supportability/DistributedTrace/CreatePayload/Exception".freeze

        def create_distributed_trace_payload
          return unless Agent.config[:'distributed_tracing.enabled']
          self.distributed_trace_payload_created = true
          payload = DistributedTracePayload.for_transaction self
          NewRelic::Agent.increment_metric SUPPORTABILITY_CREATE_PAYLOAD_SUCCESS
          payload
        rescue => e
          NewRelic::Agent.increment_metric SUPPORTABILITY_CREATE_PAYLOAD_EXCEPTION
          NewRelic::Agent.logger.warn "Failed to create distributed trace payload", e
          nil
        end

        SUPPORTABILITY_ACCEPT_PAYLOAD_SUCCESS   = "Supportability/DistributedTrace/AcceptPayload/Success".freeze
        SUPPORTABILITY_ACCEPT_PAYLOAD_EXCEPTION = "Supportability/DistributedTrace/AcceptPayload/Exception".freeze

        def accept_distributed_trace_payload payload
          return unless Agent.config[:'distributed_tracing.enabled']
          return false if check_payload_ignored(payload)
          return false unless payload = decode_payload(payload)
          return false unless check_valid_version(payload)
          return false unless check_trusted_account(payload)

          assign_payload_and_sampling_params(payload)

          NewRelic::Agent.increment_metric SUPPORTABILITY_ACCEPT_PAYLOAD_SUCCESS
          true
        rescue => e
          NewRelic::Agent.increment_metric SUPPORTABILITY_ACCEPT_PAYLOAD_EXCEPTION
          NewRelic::Agent.logger.warn "Failed to accept distributed trace payload", e
          false
        end

        def trace_id
          if distributed_trace_payload
            distributed_trace_payload.trace_id
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

        private

        SUPPORTABILITY_CREATE_BEFORE_ACCEPT_PAYLOAD   = "Supportability/DistributedTrace/AcceptPayload/Ignored/CreateBeforeAccept".freeze
        SUPPORTABILITY_MULTIPLE_ACCEPT_PAYLOAD        = "Supportability/DistributedTrace/AcceptPayload/Ignored/Multiple".freeze
        SUPPORTABILITY_PAYLOAD_ACCEPT_IGNORED_NULL    = "Supportability/DistributedTrace/AcceptPayload/Ignored/Null".freeze
        SUPPORTABILITY_PAYLOAD_ACCEPT_IGNORED_BROWSER = "Supportability/DistributedTrace/AcceptPayload/Ignored/BrowserAgentInjected".freeze

        def check_payload_ignored(payload)
          if payload.nil?
            NewRelic::Agent.increment_metric SUPPORTABILITY_PAYLOAD_ACCEPT_IGNORED_NULL
            return true
          elsif distributed_trace_payload
            NewRelic::Agent.increment_metric SUPPORTABILITY_MULTIPLE_ACCEPT_PAYLOAD
            return true
          elsif distributed_trace_payload_created?
            NewRelic::Agent.increment_metric SUPPORTABILITY_CREATE_BEFORE_ACCEPT_PAYLOAD
            return true
          end
          false
        end

        SUPPORTABILITY_PAYLOAD_ACCEPT_IGNORED_PARSE_EXCEPTION = "Supportability/DistributedTrace/AcceptPayload/ParseException".freeze
        LBRACE = "{".freeze

        def decode_payload(payload)
          if payload.start_with? LBRACE
            DistributedTracePayload.from_json payload
          else
            DistributedTracePayload.from_http_safe payload
          end
        rescue => e
          NewRelic::Agent.increment_metric SUPPORTABILITY_PAYLOAD_ACCEPT_IGNORED_PARSE_EXCEPTION
          NewRelic::Agent.logger.warn "Error parsing distributed trace payload", e
          nil
        end

        SUPPORTABILITY_PAYLOAD_ACCEPT_IGNORED_MAJOR_VERSION = "Supportability/DistributedTrace/AcceptPayload/Ignored/MajorVersion".freeze

        def check_valid_version(payload)
          if DistributedTracePayload.major_version_matches?(payload)
            true
          else
            NewRelic::Agent.increment_metric SUPPORTABILITY_PAYLOAD_ACCEPT_IGNORED_MAJOR_VERSION
            false
          end
        end

        SUPPORTABILITY_PAYLOAD_ACCEPT_UNTRUSTED_ACCOUNT = "Supportability/DistributedTrace/AcceptPayload/Ignored/UntrustedAccount".freeze

        def check_trusted_account(payload)
          trusted_account_ids = NewRelic::Agent.config[:trusted_account_ids]
          trusted = trusted_account_ids.include?(payload.parent_account_id.to_i)

          unless trusted
            NewRelic::Agent.increment_metric SUPPORTABILITY_PAYLOAD_ACCEPT_UNTRUSTED_ACCOUNT
            return false
          end

          true
        end

        def assign_payload_and_sampling_params(payload)
          self.distributed_trace_payload = payload

          unless payload.sampled.nil?
            self.sampled = payload.sampled
            self.priority = payload.priority if payload.priority
          end
        end
      end
    end
  end
end

