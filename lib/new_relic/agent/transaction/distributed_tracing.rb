# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/distributed_tracing/distributed_trace_payload'
require 'new_relic/agent/distributed_tracing/distributed_trace_intrinsics'
require 'new_relic/agent/distributed_tracing/distributed_trace_metrics'

module NewRelic
  module Agent
    class Transaction
      module DistributedTracing
        attr_accessor :distributed_trace_payload
        attr_writer :distributed_trace_payload_created

        SUPPORTABILITY_DISTRIBUTED_TRACE              = "Supportability/DistributedTrace"
        SUPPORTABILITY_CREATE_PAYLOAD                 = "#{SUPPORTABILITY_DISTRIBUTED_TRACE}/CreatePayload"
        SUPPORTABILITY_ACCEPT_PAYLOAD                 = "#{SUPPORTABILITY_DISTRIBUTED_TRACE}/AcceptPayload"
        SUPPORTABILITY_CREATE_PAYLOAD_SUCCESS         = "#{SUPPORTABILITY_CREATE_PAYLOAD}/Success"
        SUPPORTABILITY_CREATE_PAYLOAD_EXCEPTION       = "#{SUPPORTABILITY_CREATE_PAYLOAD}/Exception"
        SUPPORTABILITY_ACCEPT_PAYLOAD_SUCCESS         = "#{SUPPORTABILITY_ACCEPT_PAYLOAD}/Success"
        SUPPORTABILITY_ACCEPT_PAYLOAD_EXCEPTION       = "#{SUPPORTABILITY_ACCEPT_PAYLOAD}/Exception"

        SUPPORTABILITY_CREATE_BEFORE_ACCEPT_PAYLOAD   = "#{SUPPORTABILITY_ACCEPT_PAYLOAD}/Ignored/CreateBeforeAccept"
        SUPPORTABILITY_MULTIPLE_ACCEPT_PAYLOAD        = "#{SUPPORTABILITY_ACCEPT_PAYLOAD}/Ignored/Multiple"
        SUPPORTABILITY_PAYLOAD_ACCEPT_IGNORED_NULL    = "#{SUPPORTABILITY_ACCEPT_PAYLOAD}/Ignored/Null"
        SUPPORTABILITY_PAYLOAD_ACCEPT_IGNORED_BROWSER = "#{SUPPORTABILITY_ACCEPT_PAYLOAD}/Ignored/BrowserAgentInjected"

        def distributed_trace_payload_created?
          @distributed_trace_payload_created ||= false
        end

        def create_distributed_trace_payload
          unless nr_distributed_tracing_enabled?
            NewRelic::Agent.logger.warn "Not configured to create New Relic distributed trace payload"
            return
          end
          @distributed_trace_payload_created = true
          payload = DistributedTracePayload.for_transaction transaction
          NewRelic::Agent.increment_metric SUPPORTABILITY_CREATE_PAYLOAD_SUCCESS
          payload
        rescue => e
          NewRelic::Agent.increment_metric SUPPORTABILITY_CREATE_PAYLOAD_EXCEPTION
          NewRelic::Agent.logger.warn "Failed to create distributed trace payload", e
          nil
        end

        def accept_distributed_trace_payload payload
          unless nr_distributed_tracing_enabled?
            NewRelic::Agent.logger.warn "Not configured to accept New Relic distributed trace payload"
            return
          end
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

        def append_distributed_trace_info payload
          return unless Agent.config[:'distributed_tracing.enabled']

          DistributedTraceIntrinsics.copy_from_transaction \
            transaction,
            distributed_trace_payload,
            payload
        end

        private

        NEWRELIC_HEADER   = "newrelic"

        def nr_distributed_tracing_enabled?
          Agent.config[:'distributed_tracing.enabled'] &&
          (Agent.config[:'distributed_tracing.format'] == NEWRELIC_HEADER)
        end

        def nr_distributed_tracing_active?
          nr_distributed_tracing_enabled? && Agent.instance.connected?
        end


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
          @distributed_trace_payload = payload
          transaction.trace_id = payload.trace_id
          transaction.parent_transaction_id = payload.transaction_id
          transaction.parent_span_id = payload.id

          unless payload.sampled.nil?
            transaction.sampled = payload.sampled
            transaction.priority = payload.priority if payload.priority
          end
        end
      end
    end
  end
end

