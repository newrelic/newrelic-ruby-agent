# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Datastores
      module MetricHelper
        ROLLUP_METRIC        = "Datastore/all".freeze
        ALL_CONTEXT_METRIC   = "Datastore/allWeb".freeze
        OTHER_CONTEXT_METRIC = "Datastore/allOther".freeze

        def self.statement_metric_for(product, collection, operation)
          "Datastore/statement/#{product}/#{collection}/#{operation}"
        end

        def self.operation_metric_for(product, operation)
          "Datastore/operation/#{product}/#{operation}"
        end

        def self.context_metric
          if NewRelic::Agent::Transaction.recording_web_transaction?
            ALL_CONTEXT_METRIC
          else
            OTHER_CONTEXT_METRIC
          end
        end

        def self.metrics_for(product, collection, operation)
          [
            ROLLUP_METRIC,
            context_metric,
            statement_metric_for(product, collection, operation),
            operation_metric_for(product, operation)
          ]
        end

        def self.active_record_metric_for_name(name)
          return unless name && name.respond_to?(:split)
          parts = name.split
          return if parts.size > 2

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

        PRODUCT_NAMES = {
          "MySQL" => "MySQL",
          "Mysql2" => "MySQL",
          "PostgreSQL" => "Postgres",
          "SQLite" => "SQLite"
        }.freeze

        def self.active_record_product_name_from_adapter(adapter_name)
          PRODUCT_NAMES.fetch(adapter_name, "ActiveRecord")
        end
      end
    end
  end
end
