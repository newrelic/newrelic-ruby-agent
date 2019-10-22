# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/distributed_trace_payload'
require 'new_relic/agent/distributed_trace_intrinsics'
require 'new_relic/agent/distributed_trace_metrics'

module NewRelic
  module Agent
    class Transaction
      module DistributedTracing
        attr_accessor :distributed_trace_payload

        SUPPORTABILITY_CREATE_PAYLOAD_SUCCESS   = "Supportability/DistributedTrace/CreatePayload/Success".freeze
        SUPPORTABILITY_CREATE_PAYLOAD_EXCEPTION = "Supportability/DistributedTrace/CreatePayload/Exception".freeze

        def create_distributed_trace_payload
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
          return false unless check_payload_present(payload)
          return false unless payload = decode_payload(payload)
          return false unless check_required_fields_present(payload)
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

        def distributed_trace_payload_created?
          @distributed_trace_payload_created ||=  false
        end

        attr_writer :distributed_trace_payload_created

        def append_distributed_trace_info transaction_payload
          return unless Agent.config[:'distributed_tracing.enabled']
          DistributedTraceIntrinsics.copy_from_transaction \
            self,
            distributed_trace_payload,
            transaction_payload
        end

        NR_FORMAT = "nr".freeze

        def nr_distributed_tracing_enabled?
          Agent.config[:'distributed_tracing.enabled'] && (Agent.config[:'distributed_tracing.format'] == NR_FORMAT) && Agent.instance.connected?
        end

        private

        SUPPORTABILITY_CREATE_BEFORE_ACCEPT_PAYLOAD   = "Supportability/DistributedTrace/AcceptPayload/Ignored/CreateBeforeAccept".freeze
        SUPPORTABILITY_MULTIPLE_ACCEPT_PAYLOAD        = "Supportability/DistributedTrace/AcceptPayload/Ignored/Multiple".freeze
        SUPPORTABILITY_PAYLOAD_ACCEPT_IGNORED_NULL    = "Supportability/DistributedTrace/AcceptPayload/Ignored/Null".freeze
        SUPPORTABILITY_PAYLOAD_ACCEPT_IGNORED_BROWSER = "Supportability/DistributedTrace/AcceptPayload/Ignored/BrowserAgentInjected".freeze

        def check_payload_ignored(payload)
          if distributed_trace_payload
            NewRelic::Agent.increment_metric SUPPORTABILITY_MULTIPLE_ACCEPT_PAYLOAD
            return true
          elsif distributed_trace_payload_created?
            NewRelic::Agent.increment_metric SUPPORTABILITY_CREATE_BEFORE_ACCEPT_PAYLOAD
            return true
          end
          false
        end

        NULL_PAYLOAD = 'null'.freeze

        def check_payload_present(payload)
          # We might be passed a Ruby `nil` object _or_ the JSON "null"
          if payload.nil? || payload == NULL_PAYLOAD
            NewRelic::Agent.increment_metric SUPPORTABILITY_PAYLOAD_ACCEPT_IGNORED_NULL
            return nil
          end

          payload
        end

        SUPPORTABILITY_PAYLOAD_ACCEPT_IGNORED_PARSE_EXCEPTION = "Supportability/DistributedTrace/AcceptPayload/ParseException".freeze
        LBRACE = "{".freeze

        def decode_payload(payload)
          decoded = if payload.start_with? LBRACE
            DistributedTracePayload.from_json payload
          else
            DistributedTracePayload.from_http_safe payload
          end

          return nil unless check_payload_present(decoded)

          decoded
        rescue => e
          NewRelic::Agent.increment_metric SUPPORTABILITY_PAYLOAD_ACCEPT_IGNORED_PARSE_EXCEPTION
          NewRelic::Agent.logger.warn "Error parsing distributed trace payload", e
          nil
        end

        def check_required_fields_present(payload)
          if \
            !payload.version.nil? &&
            !payload.parent_account_id.nil? &&
            !payload.parent_app_id.nil? &&
            !payload.parent_type.nil? &&
            (!payload.transaction_id.nil? || !payload.id.nil?) &&
            !payload.trace_id.nil? &&
            !payload.timestamp.nil?

            true
          else
            NewRelic::Agent.increment_metric SUPPORTABILITY_PAYLOAD_ACCEPT_IGNORED_PARSE_EXCEPTION
            false
          end
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
          compare_key = payload.trusted_account_key || payload.parent_account_id
          unless compare_key == NewRelic::Agent.config[:trusted_account_key]
            NewRelic::Agent.increment_metric SUPPORTABILITY_PAYLOAD_ACCEPT_UNTRUSTED_ACCOUNT
            return false
          end
          true
        end

        def assign_payload_and_sampling_params(payload)
          self.distributed_trace_payload = payload
          @trace_id = payload.trace_id
          @parent_transaction_id = payload.transaction_id
          @parent_span_id = payload.id

          unless payload.sampled.nil?
            self.sampled = payload.sampled
            self.priority = payload.priority if payload.priority
          end
        end
      end
    end
  end
end

