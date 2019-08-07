# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.


module NewRelic
  module Agent
    module DistributedTraceMetrics
      extend self

      ALL_SUFFIX = "all".freeze
      ALL_WEB_SUFFIX = "allWeb".freeze
      ALL_OTHER_SUFFIX = "allOther".freeze

      DURATION_BY_CALLER_UNKOWN_PREFIX = "DurationByCaller/Unknown/Unknown/Unknown/Unknown".freeze
      ERRORS_BY_CALLER_UNKOWN_PREFIX = "ErrorsByCaller/Unknown/Unknown/Unknown/Unknown".freeze

      def transaction_type_suffix
        if Transaction.recording_web_transaction?
          ALL_WEB_SUFFIX
        else
          ALL_OTHER_SUFFIX
        end
      end

      def record_metrics_for_transaction transaction
        payload = if transaction.distributed_trace?
          transaction.distributed_trace_payload
        elsif transaction.trace_context_enabled?
          transaction.trace_state_payload
        end

        record_caller_by_duration_metrics transaction, payload
        record_transport_duration_metrics transaction, payload
        record_errors_by_caller_metrics transaction, payload
      end

      def record_caller_by_duration_metrics transaction, payload
        prefix = if payload
          "DurationByCaller/#{payload.parent_type}/#{payload.parent_account_id}/#{payload.parent_app_id}/#{payload.caller_transport_type}"
        else
          DURATION_BY_CALLER_UNKOWN_PREFIX
        end

        transaction.metrics.record_unscoped "#{prefix}/#{ALL_SUFFIX}",              transaction.duration
        transaction.metrics.record_unscoped "#{prefix}/#{transaction_type_suffix}", transaction.duration
      end

      def record_transport_duration_metrics transaction, payload
        return unless payload

        prefix = "TransportDuration/#{payload.parent_type}/#{payload.parent_account_id}/#{payload.parent_app_id}/#{payload.caller_transport_type}"

        transaction.metrics.record_unscoped "#{prefix}/#{ALL_SUFFIX}",              transaction.transport_duration
        transaction.metrics.record_unscoped "#{prefix}/#{transaction_type_suffix}", transaction.transport_duration
      end

      def record_errors_by_caller_metrics transaction, payload
        return unless transaction.exceptions.size > 0

        prefix = if payload
          "ErrorsByCaller/#{payload.parent_type}/#{payload.parent_account_id}/#{payload.parent_app_id}/#{payload.caller_transport_type}"
        else
          ERRORS_BY_CALLER_UNKOWN_PREFIX
        end

        transaction.metrics.record_unscoped "#{prefix}/#{ALL_SUFFIX}",              1
        transaction.metrics.record_unscoped "#{prefix}/#{transaction_type_suffix}", 1
      end
    end
  end
end
