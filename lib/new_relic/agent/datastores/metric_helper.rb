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

        ALL = "all".freeze

        def self.statement_metric_for(product, collection, operation)
          "Datastore/statement/#{product}/#{collection}/#{operation}"
        end

        def self.operation_metric_for(product, operation)
          "Datastore/operation/#{product}/#{operation}"
        end

        def self.rollup_metric
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
          current_rollup_metric = rollup_metric

          # Order of these metrics matters--the first metric in the list will
          # be treated as the scoped metric in a bunch of different cases.
          metrics = [
            operation_metric_for(product, operation),
            product_rollup_metric(current_rollup_metric, product),
            product_rollup_metric(ROLLUP_METRIC, product),
            current_rollup_metric,
            ROLLUP_METRIC
          ]
          metrics.unshift statement_metric_for(product, collection, operation) if collection

          metrics
        end

        def self.active_record_metric_for_name(name)
          return unless name && name.respond_to?(:split)
          parts = name.split
          return unless parts.size == 2

          model = parts.first
          operation_name = active_record_operation_from_name(parts.last.downcase)

          "Datastore/#{model}/#{operation_name}" if operation_name
        end

        OPERATION_NAMES = {
          'load' => 'find',
          'count' => 'find',
          'exists' => 'find',
          'find' => 'find',
          'destroy' => 'destroy',
          'create' => 'create',
          'update' => 'save',
          'save' => 'save'
        }.freeze

        def self.active_record_operation_from_name(operation)
          OPERATION_NAMES[operation]
        end

        ACTIVE_RECORD_ADAPTER_TO_PRODUCT_NAME = {
          "MySQL" => "MySQL",
          "Mysql2" => "MySQL",
          "PostgreSQL" => "Postgres",
          "SQLite" => "SQLite"
        }.freeze

        def self.product_name_from_active_record_adapter(adapter)
          ACTIVE_RECORD_ADAPTER_TO_PRODUCT_NAME.fetch(adapter, DEFAULT_PRODUCT_NAME)
        end

        def self.metrics_from_sql(product, sql) #THREAD_LOCAL_ACCESS
          operation = NewRelic::Agent::Database.parse_operation_from_query(sql) || "other"
          metrics = metrics_for(product, operation)

          txn = NewRelic::Agent::Transaction.tl_current

          if metric_override = txn && txn.database_metric_name
            metrics.shift
            metrics.unshift metric_override
          end

          metrics
        end
      end
    end
  end
end
