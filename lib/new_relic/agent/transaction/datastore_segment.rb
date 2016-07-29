# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/segment'
require 'new_relic/agent/datastores/metric_helper'
require 'new_relic/agent/database'

module NewRelic
  module Agent
    class Transaction
      class DatastoreSegment < Segment
        attr_reader :product, :operation, :collection, :sql_statement

        def initialize product, operation, collection = nil
          @product = product
          @operation = operation
          @collection = collection
          @sql_statement = nil
          super Datastores::MetricHelper.scoped_metric_for(product, operation, collection),
                Datastores::MetricHelper.unscoped_metrics_for(product, operation, collection)
        end

        def notice_sql sql
          _notice_sql sql
        end

        # @api private
        def _notice_sql sql, config=nil, explainer=nil, binds=nil, name=nil
          return unless record_sql?
          @sql_statement = Database::Statement.new sql, config, explainer, binds, name
        end

        private

        def segment_complete
          return unless sql_statement

          NewRelic::Agent.instance.transaction_sampler.notice_sql_statement(sql_statement, duration)
          NewRelic::Agent.instance.sql_sampler.notice_sql_statement(sql_statement.dup, name, duration)
        end

        def record_sql?
          transaction_state.is_sql_recorded?
        end
      end
    end
  end
end
