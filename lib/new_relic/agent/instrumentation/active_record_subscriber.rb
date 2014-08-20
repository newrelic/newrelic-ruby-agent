# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/instrumentation/active_record_helper'
require 'new_relic/agent/instrumentation/evented_subscriber'

# Listen for ActiveSupport::Notifications events for ActiveRecord query
# events.  Write metric data, transaction trace segments and slow sql
# nodes for each event.
module NewRelic
  module Agent
    module Instrumentation
      class ActiveRecordSubscriber < EventedSubscriber
        CACHED_QUERY_NAME = 'CACHE'.freeze unless defined? CACHED_QUERY_NAME

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
          event = pop_event(id)
          record_metrics(event)
          notice_sql(state, event)
        rescue => e
          log_notification_error(e, name, 'finish')
        end

        def get_explain_plan( config, query )
          connection = NewRelic::Agent::Database.get_connection(config) do
            ::ActiveRecord::Base.send("#{config[:adapter]}_connection",
                                      config)
          end
          if connection && connection.respond_to?(:execute)
            return connection.execute("EXPLAIN #{query}")
          end
        end

        def notice_sql(state, event)
          stack  = state.traced_method_stack
          config = active_record_config_for_event(event)
          metric = base_metric(event)

          # enter transaction trace segment
          frame = stack.push_frame(state, :active_record, event.time)

          NewRelic::Agent.instance.transaction_sampler \
            .notice_sql(event.payload[:sql], config,
                        Helper.milliseconds_to_seconds(event.duration),
                        state, &method(:get_explain_plan))

          NewRelic::Agent.instance.sql_sampler \
            .notice_sql(event.payload[:sql], metric, config,
                        Helper.milliseconds_to_seconds(event.duration),
                        state, &method(:get_explain_plan))

          # exit transaction trace segment
          stack.pop_frame(state, frame, metric, event.end)
        end

        def record_metrics(event) #THREAD_LOCAL_ACCESS
          base = base_metric(event)

          other_metrics = ActiveRecordHelper.rollup_metrics_for(base)
          if config = active_record_config_for_event(event)
            other_metrics << ActiveRecordHelper.remote_service_metric(config[:adapter], config[:host])
          end
          other_metrics.compact!

          NewRelic::Agent.instance.stats_engine.tl_record_scoped_and_unscoped_metrics(
            base, other_metrics,
            Helper.milliseconds_to_seconds(event.duration)
          )
        end

        def base_metric(event)
          ActiveRecordHelper.metric_for_name(event.payload[:name]) ||
            ActiveRecordHelper.metric_for_sql(NewRelic::Helper.correctly_encoded(event.payload[:sql]))
        end

        def active_record_config_for_event(event)
          return unless event.payload[:connection_id]

          connections = ::ActiveRecord::Base.connection_handler.connection_pool_list.map { |handler| handler.connections }.flatten
          connection = connections.detect { |cnxn| cnxn.object_id == event.payload[:connection_id] }

          connection.instance_variable_get(:@config) if connection
        end
      end
    end
  end
end
