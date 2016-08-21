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
          config = active_record_config(payload)
          event = ActiveRecordEvent.new(name, Time.now, nil, id, payload, @explainer, config)
          push_event(event)
        rescue => e
          log_notification_error(e, name, 'start')
        end

        def finish(name, id, payload) #THREAD_LOCAL_ACCESS
          return if payload[:name] == CACHED_QUERY_NAME
          state = NewRelic::Agent::TransactionState.tl_get
          return unless state.is_execution_traced?
          event = pop_event(id)
          event.finish
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

        def active_record_config(payload)
          return unless payload[:connection_id]

          connection = nil
          connection_id = payload[:connection_id]

          ::ActiveRecord::Base.connection_handler.connection_pool_list.each do |handler|
            connection = handler.connections.detect do |conn|
              conn.object_id == connection_id
            end

            break if connection
          end

          connection.instance_variable_get(:@config) if connection
        end

        class ActiveRecordEvent < Event
          def initialize(name, start, ending, transaction_id, payload, explainer, config)
            super(name, start, ending, transaction_id, payload)
            @explainer = explainer
            @config = config
            @segment = start_segment
          end

          # Events do not always finish in the order they are started for this subscriber.
          # The traced_method_stack expects that frames are popped off in the order that they
          # are pushed, otherwise it will continue to pop up the stack until it finds the frame
          # it expects. This will be fixed when we replace the tracer internals, but for now
          # we need to work around this limitation.
          def start_segment
            product, operation, collection = ActiveRecordHelper.product_operation_collection_for(payload[:name],
                                              sql, @config && @config[:adapter])
            segment = NewRelic::Agent::Transaction::DatastoreSegment.new product, operation, collection
            if txn = state.current_transaction
              segment.transaction = txn
            end
            segment._notice_sql sql, @config, @explainer, payload[:binds], payload[:name]
            segment.start
            segment
          end

          # See comment for start_segment as we continue to work around limitations of the
          # current tracer in this method.
          def finish
            if state.current_transaction
              state.traced_method_stack.push_segment state, @segment
            end
            @segment.finish
          end

          def state
            @state ||= NewRelic::Agent::TransactionState.tl_get
          end

          def sql
            @sql ||= Helper.correctly_encoded payload[:sql]
          end
        end
      end
    end
  end
end
