# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent

    # This is THE location to store thread local information during a transaction
    # Need a new piece of data? Add a method here, NOT a new thread local variable.
    class Tracer
      class << self
        def tl_get
          tl_state_for(Thread.current)
        end

        alias_method :state, :tl_get

        def tracing_enabled?
          state.tracing_enabled?
        end

        def current_transaction
          state.current_transaction
        end

        # Takes name or partial_name and a category.
        # Returns a Finishable (transaction or segment)
        def start_transaction_or_segment(name: nil,
                                         partial_name: nil,
                                         category: nil,
                                         options: {})
          if name.nil? && partial_name.nil?
            raise ArgumentError, 'missing required argument: name or partial_name'
          end
          if category.nil?
            raise ArgumentError, 'missing required argument: category'
          end

          if name
            options[:transaction_name] = name
          else
            options[:transaction_name] = Transaction.name_from_partial(
              partial_name,
              category
            )
          end

          if (txn = current_transaction)
            txn.create_nested_segment(category, options)
          else
            Transaction.start_new_transaction(tl_get, category, options)
          end

        rescue ArgumentError
          raise
        rescue => e
          NewRelic::Agent.logger.error("Exception during Tracer.start_transaction_or_segment", e)
          nil
        end

        # Takes name or partial_name and a category.
        # Returns a transaction instance or nil
        def start_transaction(name: nil,
                              partial_name: nil,
                              category: nil,
                              **options)
          if name.nil? && partial_name.nil?
            raise ArgumentError, 'missing required argument: name or partial_name'
          end
          if category.nil?
            raise ArgumentError, 'missing required argument: category'
          end

          return current_transaction if current_transaction

          if name
            options[:transaction_name] = name
          else
            options[:transaction_name] = Transaction.name_from_partial(
              partial_name,
              category
            )
          end

          Transaction.start_new_transaction(state,
                                            category,
                                            options)
        rescue ArgumentError
          raise
        rescue => e
          NewRelic::Agent.logger.error("Exception during Tracer.start_transaction", e)
          nil
        end

        def create_distributed_trace_payload
          if txn = current_transaction
            txn.create_distributed_trace_payload
          end
        end

        def accept_distributed_trace_payload(payload)
          if txn = current_transaction
            txn.accept_distributed_trace_payload(payload)
          end
        end

        def start_segment(name:nil,
                          unscoped_metrics:nil,
                          start_time: nil,
                          parent: nil)

          Transaction.start_segment(name: name,
                                    unscoped_metrics: unscoped_metrics,
                                    start_time: start_time,
                                    parent: parent)
        end

        def start_datastore_segment(product: nil,
                                    operation: nil,
                                    collection: nil,
                                    host: nil,
                                    port_path_or_id: nil,
                                    database_name: nil,
                                    start_time: nil,
                                    parent: nil)

          Transaction.start_datastore_segment(product: product,
                                              operation: operation,
                                              collection: collection,
                                              host: host,
                                              port_path_or_id: port_path_or_id,
                                              database_name: database_name,
                                              start_time: start_time,
                                              parent: parent)
        end

        def start_external_request_segment(library: nil,
                                           uri: nil,
                                           procedure: nil,
                                           start_time: nil,
                                           parent: nil)

          Transaction.start_external_request_segment(library: library,
                                                     uri: uri,
                                                     procedure: procedure,
                                                     start_time: start_time,
                                                     parent: parent)
        end

        def start_message_broker_segment(action: nil,
                                         library: nil,
                                         destination_type: nil,
                                         destination_name: nil,
                                         headers: nil,
                                         parameters: nil,
                                         start_time: nil,
                                         parent: nil)

          Transaction.start_message_broker_segment(action: action,
                                                   library: library,
                                                   destination_type: destination_type,
                                                   destination_name: destination_name,
                                                   headers: headers,
                                                   parameters: parameters,
                                                   start_time: start_time,
                                                   parent: parent)
        end

        # This method should only be used by Tracer for access to the
        # current thread's state or to provide read-only accessors for other threads
        #
        # If ever exposed, this requires additional synchronization
        def tl_state_for(thread)
          state = thread[:newrelic_transaction_state]

          if state.nil?
            state = Tracer::State.new
            thread[:newrelic_transaction_state] = state
          end

          state
        end

        def tl_clear
          Thread.current[:newrelic_transaction_state] = nil
        end

        alias_method :clear_state, :tl_clear
      end

      class State

        def initialize
          @untraced = []
          @current_transaction = nil
          @record_sql = nil
        end

        # This starts the timer for the transaction.
        def reset(transaction=nil)
          # We purposefully don't reset @untraced or @record_sql
          # since those are managed by NewRelic::Agent.disable_* calls explicitly
          # and (more importantly) outside the scope of a transaction

          @current_transaction = transaction
          @sql_sampler_transaction_data = nil
        end

        # Current transaction stack
        attr_reader :current_transaction

        # Execution tracing on current thread
        attr_accessor :untraced

        def push_traced(should_trace)
          @untraced << should_trace
        end

        def pop_traced
          @untraced.pop if @untraced
        end

        def is_execution_traced?
          @untraced.nil? || @untraced.last != false
        end

        alias_method :tracing_enabled?, :is_execution_traced?

        # TT's and SQL
        attr_accessor :record_sql

        def is_sql_recorded?
          @record_sql != false
        end

        # Sql Sampler Transaction Data
        attr_accessor :sql_sampler_transaction_data
      end
    end

    TransactionState = Tracer
  end
end
