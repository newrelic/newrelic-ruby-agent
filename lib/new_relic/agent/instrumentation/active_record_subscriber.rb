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
        CACHED_QUERY_NAME = 'CACHE'.freeze

        def initialize
          define_cachedp_method
          # We cache this in an instance variable to avoid re-calling method
          # on each query.
          @explainer = method(:get_explain_plan)
          super
        end

        # The cached? method is dynamically defined based on ActiveRecord version.
        # This file can and often is required before ActiveRecord is loaded. For
        # that reason we define the cache? method in initialize. The behavior
        # difference is that AR 5.1 includes a key in the payload to check,
        # where older versions set the :name to CACHE.

        def define_cachedp_method
          # we don't expect this to be called more than once, but we're being
          # defensive.
          return if defined?(cached?)
          if ::ActiveRecord::VERSION::STRING >= "5.1.0"
            def cached?(payload)
              payload.fetch(:cached, false)
            end
          else
            def cached?(payload)
              payload[:name] == CACHED_QUERY_NAME
            end
          end
        end

        def start(name, id, payload) #THREAD_LOCAL_ACCESS
          return if cached?(payload)
          return unless NewRelic::Agent.tl_is_execution_traced?
          config = active_record_config(payload)
          event = ActiveRecordEvent.new(name, Time.now, nil, id, payload, @explainer, config)
          push_event(event)
        rescue => e
          log_notification_error(e, name, 'start')
        end

        def finish(name, id, payload) #THREAD_LOCAL_ACCESS
          return if cached?(payload)
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
        rescue => e
          NewRelic::Agent.logger.debug "Couldn't fetch the explain plan for #{statement} due to #{e}"
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

            host = nil
            port_path_or_id = nil
            database = nil

            if ActiveRecordHelper::InstanceIdentification.supported_adapter?(@config)
              host = ActiveRecordHelper::InstanceIdentification.host(@config)
              port_path_or_id = ActiveRecordHelper::InstanceIdentification.port_path_or_id(@config)
              database = @config && @config[:database]
            end

            segment = NewRelic::Agent::Transaction::DatastoreSegment.new product, operation, collection, host, port_path_or_id, database
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
            if txn = state.current_transaction
              txn.add_segment @segment
            end
            @segment.finish if @segment
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
