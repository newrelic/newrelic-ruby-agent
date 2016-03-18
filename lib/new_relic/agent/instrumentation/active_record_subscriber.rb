# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/instrumentation/active_record_helper'
require 'new_relic/agent/instrumentation/evented_subscriber'

# Listen for ActiveSupport::Notifications events for ActiveRecord query
# events.  Write metric data, transaction trace nodes and slow sql
# nodes for each event.
module NewRelic
  module Agent
    module Instrumentation
      class ActiveRecordSubscriber < EventedSubscriber
        CACHED_QUERY_NAME = 'CACHE'.freeze unless defined? CACHED_QUERY_NAME

        def initialize
          # We cache this in an instance variable to avoid re-calling method
          # on each query.
          @explainer = method(:get_explain_plan)
          super
        end

        def start(name, id, payload) #THREAD_LOCAL_ACCESS
          return if payload[:name] == CACHED_QUERY_NAME
          return unless NewRelic::Agent.tl_is_execution_traced?
          super
        rescue => e
          log_notification_error(e, name, 'start')
        end

        def finish(name, id, payload) #THREAD_LOCAL_ACCESS
          return if payload[:name] == CACHED_QUERY_NAME
          state = NewRelic::Agent::TransactionState.tl_get
          return unless state.is_execution_traced?
          event  = pop_event(id)
          config = active_record_config_for_event(event)
          base_metric = record_metrics(event, config)
          notice_sql(state, event, config, base_metric)
        rescue => e
          log_notification_error(e, name, 'finish')
        end

        def get_explain_plan(statement)
          connection = NewRelic::Agent::Database.get_connection(statement.config) do
            ::ActiveRecord::Base.send("#{statement.config[:adapter]}_connection",
                                      statement.config)
          end
          if connection && connection.respond_to?(:exec_query)
            return connection.exec_query("EXPLAIN #{statement.sql}",
                                         "Explain #{statement.name}",
                                         statement.binds)
          end
        end

        def notice_sql(state, event, config, metric)
          stack  = state.traced_method_stack

          # enter transaction trace node
          frame = stack.push_frame(state, :active_record, event.time)

          NewRelic::Agent.instance.transaction_sampler \
            .notice_sql(event.payload[:sql], config,
                        Helper.milliseconds_to_seconds(event.duration),
                        state, @explainer, event.payload[:binds], event.payload[:name])

          NewRelic::Agent.instance.sql_sampler \
            .notice_sql(event.payload[:sql], metric, config,
                        Helper.milliseconds_to_seconds(event.duration),
                        state, @explainer, event.payload[:binds], event.payload[:name])

          # exit transaction trace node
          stack.pop_frame(state, frame, metric, event.end)
        end

        def record_metrics(event, config) #THREAD_LOCAL_ACCESS
          base, *other_metrics = ActiveRecordHelper.metrics_for(event.payload[:name],
                                                               NewRelic::Helper.correctly_encoded(event.payload[:sql]),
                                                               config && config[:adapter])

          NewRelic::Agent.instance.stats_engine.tl_record_scoped_and_unscoped_metrics(
            base, other_metrics,
            Helper.milliseconds_to_seconds(event.duration))

          base
        end

        def active_record_config_for_event(event)
          return unless event.payload[:connection_id]

          connection = nil
          connection_id = event.payload[:connection_id]

          ::ActiveRecord::Base.connection_handler.connection_pool_list.each do |handler|
            connection = handler.connections.detect do |conn|
              conn.object_id == connection_id
            end

            break if connection
          end

          connection.instance_variable_get(:@config) if connection
        end
      end
    end
  end
end
