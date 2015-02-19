# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/datastores/metric_helper'

module NewRelic
  module Agent
    module Instrumentation
      module ActiveRecordHelper
        module_function

        ACTIVE_RECORD = "ActiveRecord".freeze
        OTHER         = "other".freeze

        def metrics_for(name, sql, config=nil)
          product = map_product(config)
          operation, model = operation_and_model(name, sql)

          NewRelic::Agent::Datastores::MetricHelper.metrics_for(product,
                                                                operation,
                                                                model)
        end

        def operation_and_model(name, sql)
          if name && name.respond_to?(:split)
            parts = name.split(' ')
            if parts.size == 2
              model = parts.first
              operation = map_operation(parts)

              return [operation, model]
            end
          end

          [NewRelic::Agent::Database.parse_operation_from_query(sql) || OTHER, nil]
        end

        OPERATION_NAMES = {
          'load' => 'find',
          'count' => 'find',
          'exists' => 'find',
          'update' => 'save',
        }.freeze

        def map_operation(parts)
          operation = parts.last.downcase
          OPERATION_NAMES.fetch(operation, operation)
        end

        PRODUCT_NAMES = {
          "mysql"      => "MySQL",
          "mysql2"     => "MySQL",
          "postgresql" => "Postgres",
          "sqlite3"    => "SQLite"
        }.freeze

        ACTIVE_RECORD_DEFAULT_PRODUCT_NAME = "ActiveRecord".freeze

        def map_product(config)
          PRODUCT_NAMES.fetch(adapter_name(config),
                              ACTIVE_RECORD_DEFAULT_PRODUCT_NAME)
        end

        def adapter_name(config)
          config[:adapter] if config
        end

      end
    end
  end
end
