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
        DEFAULT_PRODUCT_NAME = "ActiveRecord".freeze
        OTHER = "Other".freeze

        ALL = "all".freeze
        ALL_WEB = "allWeb".freeze
        ALL_OTHER = "allOther".freeze

        def self.statement_metric_for(product, collection, operation)
          "Datastore/statement/#{product}/#{collection}/#{operation}"
        end

        def self.operation_metric_for(product, operation)
          "Datastore/operation/#{product}/#{operation}"
        end

        def self.product_suffixed_rollup(product, suffix)
          "Datastore/#{product}/#{suffix}"
        end

        def self.product_rollup(product)
          "Datastore/#{product}/all"
        end

        def self.suffixed_rollup(suffix)
          "Datastore/#{suffix}"
        end

        def self.all_suffix
          if NewRelic::Agent::Transaction.recording_web_transaction?
            ALL_WEB
          else
            ALL_OTHER
          end
        end

        def self.metrics_for(product, operation, collection = nil, generic_product = nil)
          if overrides = overridden_operation_and_collection
            if should_override?(overrides, product, generic_product)
              operation  = overrides[0] || operation
              collection = overrides[1] || collection
            end
          end

          suffix = all_suffix

          # Order of these metrics matters--the first metric in the list will
          # be treated as the scoped metric in a bunch of different cases.
          metrics = [
            operation_metric_for(product, operation),
            product_suffixed_rollup(product, suffix),
            product_rollup(product),
            suffixed_rollup(suffix),
            ROLLUP_METRIC
          ]

          metrics.unshift statement_metric_for(product, collection, operation) if collection

          metrics
        end

        def self.metrics_from_sql(product, sql)
          operation = NewRelic::Agent::Database.parse_operation_from_query(sql) || OTHER
          metrics_for(product, operation)
        end

        # Allow Transaction#with_database_metric_name to override our
        # collection and operation
        def self.overridden_operation_and_collection #THREAD_LOCAL_ACCESS
          state = NewRelic::Agent::TransactionState.tl_get
          txn   = state.current_transaction
          txn ? txn.instrumentation_state[:datastore_override] : nil
        end

        # If the override declared a product affiliation, abide by that
        # ActiveRecord has database-specific product names, so we recognize
        # it by the generic_product it passes.
        def self.should_override?(overrides, product, generic_product)
          override_product = overrides[2]

          override_product.nil? ||
            override_product == product ||
            override_product == generic_product
        end
      end
    end
  end
end
