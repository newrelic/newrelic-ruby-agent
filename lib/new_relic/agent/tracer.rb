# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction'
require 'new_relic/agent/transaction/segment'
require 'new_relic/agent/transaction/datastore_segment'
require 'new_relic/agent/transaction/external_request_segment'
require 'new_relic/agent/transaction/message_broker_segment'

module NewRelic
  module Agent
    class Tracer
      class << self
        def state
          state_for(Thread.current)
        end

        alias_method :tl_get, :state

        def tracing_enabled?
          state.tracing_enabled?
        end

        def current_transaction
          state.current_transaction
        end

        def in_transaction(name: nil,
                           partial_name: nil,
                           category: nil,
                           options: {})

          finishable = start_transaction_or_segment(
            name: name,
            partial_name: partial_name,
            category: category,
            options: options
          )

          begin
            # We shouldn't raise from Tracer.start_transaction_or_segment, but
            # only wrap the yield to be absolutely sure we don't report agent
            # problems as app errors
            yield
          rescue => e
            current_transaction.notice_error(e)
            raise e
          ensure
            finishable.finish if finishable
          end
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
          log_error('start_transaction_or_segment', e)
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
          log_error('start_transaction', e)
        end

        def create_distributed_trace_payload
          return unless txn = current_transaction
          txn.create_distributed_trace_payload
        end

        def accept_distributed_trace_payload(payload)
          return unless txn = current_transaction
          txn.accept_distributed_trace_payload(payload)
        end

        def current_segment
          return unless txn = current_transaction
          txn.current_segment
        end

        def start_segment(name:nil,
                          unscoped_metrics:nil,
                          start_time: nil,
                          parent: nil)

          # ruby 2.0.0 does not support required kwargs
          raise ArgumentError, 'missing required argument: name' if name.nil?

          segment = Transaction::Segment.new name, unscoped_metrics, start_time
          start_and_add_segment segment, parent

        rescue ArgumentError
          raise
        rescue => e
          log_error('start_segment', e)
        end

        UNKNOWN = "Unknown".freeze
        OTHER = "other".freeze

        def start_datastore_segment(product: nil,
                                    operation: nil,
                                    collection: nil,
                                    host: nil,
                                    port_path_or_id: nil,
                                    database_name: nil,
                                    start_time: nil,
                                    parent: nil)

          product ||= UNKNOWN
          operation ||= OTHER

          segment = Transaction::DatastoreSegment.new product, operation, collection, host, port_path_or_id, database_name
          start_and_add_segment segment, parent

        rescue ArgumentError
          raise
        rescue => e
          log_error('start_datastore_segment', e)
        end

        def start_external_request_segment(library: nil,
                                           uri: nil,
                                           procedure: nil,
                                           start_time: nil,
                                           parent: nil)

          # ruby 2.0.0 does not support required kwargs
          raise ArgumentError, 'missing required argument: library' if library.nil?
          raise ArgumentError, 'missing required argument: uri' if uri.nil?
          raise ArgumentError, 'missing required argument: procedure' if procedure.nil?

          segment = Transaction::ExternalRequestSegment.new library, uri, procedure, start_time
          start_and_add_segment segment, parent

        rescue ArgumentError
          raise
        rescue => e
          log_error('start_external_request_segment', e)
        end

        def start_message_broker_segment(action: nil,
                                         library: nil,
                                         destination_type: nil,
                                         destination_name: nil,
                                         headers: nil,
                                         parameters: nil,
                                         start_time: nil,
                                         parent: nil)

          # ruby 2.0.0 does not support required kwargs
          raise ArgumentError, 'missing required argument: action' if action.nil?
          raise ArgumentError, 'missing required argument: library' if library.nil?
          raise ArgumentError, 'missing required argument: destination_type' if destination_type.nil?
          raise ArgumentError, 'missing required argument: destination_name' if destination_name.nil?

          segment = Transaction::MessageBrokerSegment.new(
            action: action,
            library: library,
            destination_type: destination_type,
            destination_name: destination_name,
            headers: headers,
            parameters: parameters,
            start_time: start_time
          )
          start_and_add_segment segment, parent

        rescue ArgumentError
          raise
        rescue => e
          log_error('start_datastore_segment', e)
        end

        # This method should only be used by Tracer for access to the
        # current thread's state or to provide read-only accessors for other threads
        #
        # If ever exposed, this requires additional synchronization
        def state_for(thread)
          state = thread[:newrelic_tracer_state]

          if state.nil?
            state = Tracer::State.new
            thread[:newrelic_tracer_state] = state
          end

          state
        end

        alias_method :tl_state_for, :state_for

        def clear_state
          Thread.current[:newrelic_tracer_state] = nil
        end

        alias_method :tl_clear, :clear_state

        private

        def start_and_add_segment segment, parent = nil
          tracer_state = state
          if (txn = tracer_state.current_transaction) &&
            tracer_state.tracing_enabled?
            txn.add_segment segment, parent
          else
            segment.record_metrics = false
          end
          segment.start
          segment
        end

        def log_error(method_name, exception)
          NewRelic::Agent.logger.error("Exception during Tracer.#{method_name}", exception)
          nil
        end
      end

      # This is THE location to store thread local information during a transaction
      # Need a new piece of data? Add a method here, NOT a new thread local variable.
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
