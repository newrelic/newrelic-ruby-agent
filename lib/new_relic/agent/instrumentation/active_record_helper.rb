# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/datastores/metric_helper'
require 'new_relic/agent/deprecator'

module NewRelic
  module Agent
    module Instrumentation
      module ActiveRecordHelper
        module_function

        ACTIVE_RECORD = "ActiveRecord".freeze unless defined?(ACTIVE_RECORD)
        OTHER         = "other".freeze unless defined?(OTHER)

        def metrics_for(name, sql, adapter_name)
          product   = map_product(adapter_name)
          splits    = split_name(name)
          model     = model_from_splits(splits)
          operation = operation_from_splits(splits, sql)

          NewRelic::Agent::Datastores::MetricHelper.metrics_for(product,
                                                                operation,
                                                                model)
        end

        # @deprecated
        def rollup_metrics_for(*_)
          NewRelic::Agent::Deprecator.deprecate("#{self.class}.rollup_metrics_for",
                                                "NewRelic::Agent::Datastores::MetricHelper.metrics_for")

          rollup_metric = if NewRelic::Agent::Transaction.recording_web_transaction?
            NewRelic::Agent::Datastores::MetricHelper::WEB_ROLLUP_METRIC
          else
            NewRelic::Agent::Datastores::MetricHelper::OTHER_ROLLUP_METRIC
          end

          [rollup_metric,
           NewRelic::Agent::Datastores::MetricHelper::ROLLUP_METRIC]
        end

        SPACE = ' '.freeze unless defined?(SPACE)
        EMPTY = [].freeze unless defined?(EMPTY)

        def split_name(name)
          if name && name.respond_to?(:split)
            name.split(SPACE)
          else
            EMPTY
          end
        end

        def model_from_splits(splits)
          if splits.length == 2
            splits.first
          else
            nil
          end
        end

        def operation_from_splits(splits, sql)
          if splits.length == 2
            map_operation(splits[1])
          else
            NewRelic::Agent::Database.parse_operation_from_query(sql) || OTHER
          end
        end

        # These are used primarily to optimize and avoid allocation on well
        # known operations coming in. Anything not matching the list is fine,
        # it just needs to get downcased directly for use.
        OPERATION_NAMES = {
          'Find'    => 'find',
          'Load'    => 'find',
          'Count'   => 'find',
          'Exists'  => 'find',
          'Create'  => 'create',
          'Columns' => 'columns',
          'Indexes' => 'indexes',
          'Destroy' => 'destroy',
          'Update'  => 'update',
          'Save'    => 'save'
        }.freeze unless defined?(OPERATION_NAMES)

        def map_operation(raw_operation)
          direct_op = OPERATION_NAMES[raw_operation]
          return direct_op if direct_op

          raw_operation.downcase
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

        def map_product(adapter_name)
          PRODUCT_NAMES.fetch(adapter_name,
                              ACTIVE_RECORD_DEFAULT_PRODUCT_NAME)
        end

      end
    end
  end
end
