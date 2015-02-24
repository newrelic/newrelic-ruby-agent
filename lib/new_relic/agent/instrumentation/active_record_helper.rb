# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/datastores/metric_helper'

module NewRelic
  module Agent
    module Instrumentation
      module ActiveRecordHelper
        module_function

        ACTIVE_RECORD = "ActiveRecord".freeze unless defined?(ACTIVE_RECORD)
        OTHER         = "other".freeze unless defined?(OTHER)

        def metrics_for(name, sql, config=nil)
          product = map_product(config)
          operation, model = operation_and_model(name, sql)

          NewRelic::Agent::Datastores::MetricHelper.metrics_for(product,
                                                                operation,
                                                                model)
        end

        def operation_and_model(name, sql)
          if name && name.respond_to?(:split)
            model, raw_operation = name.split(' ')
            if model && raw_operation
              operation = map_operation(raw_operation)
              return [operation, model]
            end
          end

          [NewRelic::Agent::Database.parse_operation_from_query(sql) || OTHER, nil]
        end

        OPERATION_NAMES = {
          'load'   => 'find',
          'count'  => 'find',
          'exists' => 'find',
        }.freeze unless defined?(OPERATION_NAMES)

        def map_operation(raw_operation)
          operation = raw_operation.downcase
          OPERATION_NAMES.fetch(operation, operation)
        end

        PRODUCT_NAMES = {
          "mysql"      => "MySQL",
          "mysql2"     => "MySQL",

          "postgresql" => "Postgres",

          "sqlite3"    => "SQLite",

          # https://rubygems.org/gems/activerecord-jdbcpostgresql-adapter
          "jdbcmysql"  => "MySQL",

          # https://rubygems.org/gems/activerecord-jdbcpostgresql-adapter
          "jdbcpostgresql" => "Postgres",

          # https://rubygems.org/gems/activerecord-jdbcsqlite3-adapter
          "jdbcsqlite3"    => "SQLite",

          # https://rubygems.org/gems/activerecord-jdbcderby-adapter
          "derby"      => "Derby",
          "jdbcderby"  => "Derby",

          # https://rubygems.org/gems/activerecord-jdbc-adapter
          "jdbc"       => "JDBC",

          # https://rubygems.org/gems/activerecord-jdbcmssql-adapter
          "jdbcmssql"  => "MSSQL",
          "mssql"      => "MSSQL",

          # https://rubygems.org/gems/activerecord-sqlserver-adapter
          "sqlserver"  => "MSSQL",

          # https://rubygems.org/gems/activerecord-odbc-adapter
          "odbc"       => "ODBC",

          # https://rubygems.org/gems/activerecord-oracle_enhanced-adapter
          "oracle_enhanced" => "Oracle"
        }.freeze unless defined?(PRODUCT_NAMES)

        ACTIVE_RECORD_DEFAULT_PRODUCT_NAME = "ActiveRecord".freeze unless defined?(ACTIVE_RECORD_DEFAULT_PRODUCT_NAME)

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
