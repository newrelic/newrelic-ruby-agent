# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent

    # This is THE location to store thread local information during a transaction
    # Need a new piece of data? Add a method here, NOT a new thread local variable.
    class TransactionState
      class << self
        def tl_get
          tl_state_for(Thread.current)
        end

        alias_method :trace_state, :tl_get

        def tracing_enabled?
          trace_state.tracing_enabled?
        end

        def current_transaction
          trace_state.current_transaction
        end

        # A more ergonomic API would be to have transaction derive the
        # category from the transaction name and we should explore this as an
        # option.
        def start_transaction(name: nil, category: nil, **options)
          raise ArgumentError, 'missing required argument: name' if name.nil?
          raise ArgumentError, 'missing required argument: category' if category.nil?

          state = trace_state
          return state.current_transaction if state.current_transaction

          options[:transaction_name] =  name

          Transaction.start_new_transaction(trace_state,
                                            category,
                                            options)
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

        # This method should only be used by TransactionState for access to the
        # current thread's state or to provide read-only accessors for other threads
        #
        # If ever exposed, this requires additional synchronization
        def tl_state_for(thread)
          state = thread[:newrelic_transaction_state]

          if state.nil?
            state = TransactionState.new
            thread[:newrelic_transaction_state] = state
          end

          state
        end

        def tl_clear
          Thread.current[:newrelic_transaction_state] = nil
        end
      end

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

        @timings = nil
        @request = nil
        @current_transaction = transaction


        @is_cross_app_caller = false
        @client_cross_app_id = nil
        @referring_transaction_info = nil

        @sql_sampler_transaction_data = nil

        @busy_entries = 0
      end

      def timings
        @timings ||= TransactionTimings.new(transaction_queue_time, transaction_start_time, transaction_name)
      end

      # Cross app tracing
      # Because we need values from headers before the transaction actually starts
      attr_accessor :client_cross_app_id, :referring_transaction_info, :is_cross_app_caller

      def is_cross_app_caller?
        @is_cross_app_caller
      end

      def is_cross_app_callee?
        referring_transaction_info != nil
      end

      def is_cross_app?
        is_cross_app_caller? || is_cross_app_callee?
      end

      # Request data
      attr_accessor :request

      def request_guid
        return nil unless current_transaction
        current_transaction.guid
      end

      # Current transaction stack
      attr_reader   :current_transaction

      def transaction_start_time
        current_transaction.start_time if current_transaction
      end

      def transaction_queue_time
        current_transaction.nil? ? 0.0 : current_transaction.queue_time
      end

      def transaction_name
        current_transaction.nil? ? nil : current_transaction.best_name
      end

      def in_background_transaction?
        !current_transaction.nil? && !current_transaction.recording_web_transaction?
      end

      def in_web_transaction?
        !current_transaction.nil? && current_transaction.recording_web_transaction?
      end

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

      # Busy calculator
      attr_accessor :busy_entries

      # Sql Sampler Transaction Data
      attr_accessor :sql_sampler_transaction_data
    end

    Tracer = TransactionState
  end
end
