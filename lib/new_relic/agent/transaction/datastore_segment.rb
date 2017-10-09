# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/segment'
require 'new_relic/agent/datastores/metric_helper'
require 'new_relic/agent/database'
require 'new_relic/agent/hostname'

module NewRelic
  module Agent
    class Transaction
      class DatastoreSegment < Segment

        UNKNOWN = 'unknown'.freeze

        attr_reader :product, :operation, :collection, :sql_statement, :nosql_statement, :host, :port_path_or_id
        attr_accessor :database_name


        def initialize product, operation, collection = nil, host = nil, port_path_or_id = nil, database_name = nil, start_time = nil
          @product = product
          @operation = operation
          @collection = collection
          @sql_statement = nil
          @nosql_statement = nil
          set_instance_info host, port_path_or_id
          @database_name = database_name ? database_name.to_s : nil
          super Datastores::MetricHelper.scoped_metric_for(product, operation, collection),
                nil,
                start_time
        end

        def set_instance_info host = nil, port_path_or_id = nil
          port_path_or_id = port_path_or_id.to_s if port_path_or_id
          host_present = host && !host.empty?
          ppi_present = port_path_or_id && !port_path_or_id.empty?

          host = NewRelic::Agent::Hostname.get_external host if host_present

          case
          when host_present && ppi_present
            @host = host
            @port_path_or_id = port_path_or_id

          when host_present && !ppi_present
            @host = host
            @port_path_or_id = UNKNOWN

          when !host_present && ppi_present
            @host = UNKNOWN
            @port_path_or_id = port_path_or_id

          else
            @host = @port_path_or_id = nil
          end
        end

        def notice_sql sql
          _notice_sql sql
          nil
        end

        # @api private
        def _notice_sql sql, config=nil, explainer=nil, binds=nil, name=nil
          return unless record_sql?
          @sql_statement = Database::Statement.new sql, config, explainer, binds, name, host, port_path_or_id, database_name
        end

        def notice_nosql_statement nosql_statement
          return unless record_sql?
          @nosql_statement = Database.truncate_query(nosql_statement)
          nil
        end

        def record_metrics
          @unscoped_metrics = Datastores::MetricHelper.unscoped_metrics_for(product, operation, collection, host, port_path_or_id)
          super
        end

        private

        def segment_complete
          notice_sql_statement if sql_statement
          notice_statement if nosql_statement
          add_instance_parameters
          add_database_name_parameter
          add_backtrace_parameter

          super
        end

        def add_instance_parameters
          return unless NewRelic::Agent.config[:'datastore_tracer.instance_reporting.enabled']
          params[:host] = host if host
          params[:port_path_or_id] = port_path_or_id if port_path_or_id
        end

        def add_database_name_parameter
          return unless NewRelic::Agent.config[:'datastore_tracer.database_name_reporting.enabled']
          params[:database_name] = database_name if database_name
        end

        NEWLINE = "\n".freeze

        def add_backtrace_parameter
           return unless duration >= Agent.config[:'transaction_tracer.stack_trace_threshold']
           params[:backtrace] = caller.join(NEWLINE)
        end

        def notice_sql_statement
          params[:sql] = sql_statement
          NewRelic::Agent.instance.sql_sampler.notice_sql_statement(sql_statement.dup, name, duration)
        end

        def notice_statement
          params[:statement] = nosql_statement
        end

        def record_sql?
          transaction_state.is_sql_recorded?
        end
      end
    end
  end
end
