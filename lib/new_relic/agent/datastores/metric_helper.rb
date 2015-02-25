# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Datastores
      module MetricHelper
        ROLLUP_METRIC        = "Datastore/all".freeze
        WEB_ROLLUP_METRIC    = "Datastore/allWeb".freeze
        OTHER_ROLLUP_METRIC  = "Datastore/allOther".freeze

        ALL = "all".freeze

        def self.statement_metric_for(product, collection, operation)
          "Datastore/statement/#{product}/#{collection}/#{operation}"
        end

        def self.operation_metric_for(product, operation)
          "Datastore/operation/#{product}/#{operation}"
        end

        def self.context_metric
          if NewRelic::Agent::Transaction.recording_web_transaction?
            WEB_ROLLUP_METRIC
          else
            OTHER_ROLLUP_METRIC
          end
        end

        def self.product_rollup_metric(metric, product)
          metric.sub(ALL, "#{product}/#{ALL}")
        end

        def self.metrics_for(product, operation, collection = nil)
          current_context_metric = context_metric

          if overrides = overridden_operation_and_collection
            operation, collection = overrides
          end

          # Order of these metrics matters--the first metric in the list will
          # be treated as the scoped metric in a bunch of different cases.
          metrics = [
            operation_metric_for(product, operation),
            product_rollup_metric(current_context_metric, product),
            product_rollup_metric(ROLLUP_METRIC, product),
            current_context_metric,
            ROLLUP_METRIC
          ]

          metrics.unshift statement_metric_for(product, collection, operation) if collection

          metrics
        end

        # Allow Transaction#with_database_metric_name to override our
        # collection and operation
        def self.overridden_operation_and_collection #THREAD_LOCAL_ACCESS
          state = NewRelic::Agent::TransactionState.tl_get
          txn   = state.current_transaction
          txn ?  txn.instrumentation_state[:datastore_override] : nil
        end

      end
    end
  end
end
