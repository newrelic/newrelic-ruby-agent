# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module DistributedTraceMetrics
      extend self

      ALL_SUFFIX = "all"
      ALL_WEB_SUFFIX = "allWeb"
      ALL_OTHER_SUFFIX = "allOther"

      DURATION_BY_CALLER_UNKOWN_PREFIX = "DurationByCaller/Unknown/Unknown/Unknown/%s"
      ERRORS_BY_CALLER_UNKOWN_PREFIX = "ErrorsByCaller/Unknown/Unknown/Unknown/%s"

      def transaction_type_suffix
        if Transaction.recording_web_transaction?
          ALL_WEB_SUFFIX
        else
          ALL_OTHER_SUFFIX
        end
      end

      def record_metrics_for_transaction transaction
        return unless Agent.config[:'distributed_tracing.enabled']
        dt = transaction.distributed_tracer
        payload = dt.distributed_trace_payload || dt.trace_state_payload

        record_caller_by_duration_metrics transaction, payload
        record_transport_duration_metrics transaction, payload
        record_errors_by_caller_metrics transaction, payload
      end

      def record_caller_by_duration_metrics transaction, payload
        prefix = if payload
          "DurationByCaller/" \
          "#{payload.parent_type}/" \
          "#{payload.parent_account_id}/" \
          "#{payload.parent_app_id}/" \
          "#{transaction.distributed_tracer.caller_transport_type}"
        else
          DURATION_BY_CALLER_UNKOWN_PREFIX % transaction.distributed_tracer.caller_transport_type
        end

        transaction.metrics.record_unscoped "#{prefix}/#{ALL_SUFFIX}",              transaction.duration
        transaction.metrics.record_unscoped "#{prefix}/#{transaction_type_suffix}", transaction.duration
      end

      def record_transport_duration_metrics transaction, payload
        return unless payload

        prefix = "TransportDuration/#{payload.parent_type}/#{payload.parent_account_id}/#{payload.parent_app_id}/#{transaction.distributed_tracer.caller_transport_type}"
        duration = transaction.calculate_transport_duration payload

        transaction.metrics.record_unscoped "#{prefix}/#{ALL_SUFFIX}",              duration
        transaction.metrics.record_unscoped "#{prefix}/#{transaction_type_suffix}", duration
      end

      def record_errors_by_caller_metrics transaction, payload
        return unless transaction.exceptions.size > 0

        prefix = if payload
          "ErrorsByCaller/#{payload.parent_type}/#{payload.parent_account_id}/#{payload.parent_app_id}/#{transaction.distributed_tracer.caller_transport_type}"
        else
          ERRORS_BY_CALLER_UNKOWN_PREFIX % transaction.distributed_tracer.caller_transport_type
        end

        transaction.metrics.record_unscoped "#{prefix}/#{ALL_SUFFIX}",              1
        transaction.metrics.record_unscoped "#{prefix}/#{transaction_type_suffix}", 1
      end
    end
  end
end
