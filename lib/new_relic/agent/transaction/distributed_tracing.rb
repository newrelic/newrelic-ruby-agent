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
          distributed_trace_payload && distributed_trace_payload.transaction_id
        end

        def distributed_trace_payload_created?
          @distributed_trace_payload_created ||=  false
        end

        attr_writer :distributed_trace_payload_created

        def append_distributed_trace_info transaction_payload
          return unless Agent.config[:'distributed_tracing.enabled']
          if distributed_trace_payload
            distributed_trace_payload.assign_intrinsics self, transaction_payload
          else
            DistributedTracePayload.assign_initial_intrinsics self, transaction_payload
          end
        end

        def assign_distributed_trace_intrinsics
          return unless Agent.config[:'distributed_tracing.enabled']
          DistributedTracePayload::INTRINSIC_KEYS.each do |key|
            next unless @payload.key? key
            attributes.add_intrinsic_attribute key, @payload[key]
          end
          nil
        end

        # This method returns transport_duration in seconds. Transport duration
        # is stored in milliseconds on the payload, but it's needed in seconds
        # for metrics and intrinsics.
        def transport_duration
          return unless distributed_trace_payload
          duration = (start_time.to_f * 1000 - distributed_trace_payload.timestamp) / 1000
          duration < 0 ? 0 : duration
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
            !payload.timestamp.nil? &&
            !payload.parent_account_id.nil?

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

          unless payload.sampled.nil?
            self.sampled = payload.sampled
            self.priority = payload.priority if payload.priority
          end
        end

        ALL_SUFFIX = "all".freeze
        ALL_WEB_SUFFIX = "allWeb".freeze
        ALL_OTHER_SUFFIX = "allOther".freeze

        def transaction_type_suffix
          if Transaction.recording_web_transaction?
            ALL_WEB_SUFFIX
          else
            ALL_OTHER_SUFFIX
          end
        end

        def record_distributed_tracing_metrics
          return unless Agent.config[:'distributed_tracing.enabled']

          record_caller_by_duration_metrics
          record_transport_duration_metrics
          record_errors_by_caller_metrics
        end

        DURATION_BY_CALLER_UNKOWN_PREFIX = "DurationByCaller/Unknown/Unknown/Unknown/Unknown".freeze

        def record_caller_by_duration_metrics
          prefix = if distributed_trace?
            payload = distributed_trace_payload
            "DurationByCaller/#{payload.parent_type}/#{payload.parent_account_id}/#{payload.parent_app_id}/#{payload.caller_transport_type}"
          else
            DURATION_BY_CALLER_UNKOWN_PREFIX
          end

          metrics.record_unscoped "#{prefix}/#{ALL_SUFFIX}",              duration
          metrics.record_unscoped "#{prefix}/#{transaction_type_suffix}", duration
        end

        def record_transport_duration_metrics
          return unless distributed_trace?

          payload = distributed_trace_payload
          prefix = "TransportDuration/#{payload.parent_type}/#{payload.parent_account_id}/#{payload.parent_app_id}/#{payload.caller_transport_type}"

          metrics.record_unscoped "#{prefix}/#{ALL_SUFFIX}",              transport_duration
          metrics.record_unscoped "#{prefix}/#{transaction_type_suffix}", transport_duration
        end

        ERRORS_BY_CALLER_UNKOWN_PREFIX = "ErrorsByCaller/Unknown/Unknown/Unknown/Unknown".freeze

        def record_errors_by_caller_metrics
          return unless exceptions.size > 0

          prefix = if distributed_trace?
            payload = distributed_trace_payload
            "ErrorsByCaller/#{payload.parent_type}/#{payload.parent_account_id}/#{payload.parent_app_id}/#{payload.caller_transport_type}"
          else
            ERRORS_BY_CALLER_UNKOWN_PREFIX
          end

          metrics.record_unscoped "#{prefix}/#{ALL_SUFFIX}",              1
          metrics.record_unscoped "#{prefix}/#{transaction_type_suffix}", 1
        end
      end
    end
  end
end

