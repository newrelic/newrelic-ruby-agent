# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/traced_method_stack'

module NewRelic
  module Agent

    # This is THE location to store thread local information during a transaction
    # Need a new piece of data? Add a method here, NOT a new thread local variable.
    class TransactionState
      def self.tl_get
        tl_state_for(Thread.current)
      end

      # This method should only be used by TransactionState for access to the
      # current thread's state or to provide read-only accessors for other threads
      #
      # If ever exposed, this requires additional synchronization
      def self.tl_state_for(thread)
        state = thread[:newrelic_transaction_state]

        if state.nil?
          state = TransactionState.new
          thread[:newrelic_transaction_state] = state
        end

        state
      end

      def self.tl_clear_for_testing
        Thread.current[:newrelic_transaction_state] = nil
      end

      def initialize
        @untraced = []
        @traced_method_stack = TracedMethodStack.new
        @current_transaction = nil
        @record_tt = nil
      end

      # This starts the timer for the transaction.
      def reset(transaction=nil)
        # We purposefully don't reset @untraced, @record_tt and @record_sql
        # since those are managed by NewRelic::Agent.disable_* calls explicitly
        # and (more importantly) outside the scope of a transaction

        @timings = nil
        @request = nil
        @current_transaction = transaction

        @traced_method_stack.clear

        @is_cross_app_caller = false
        @client_cross_app_id = nil
        @referring_transaction_info = nil

        @transaction_sample_builder = nil
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

      # Current transaction stack and sample building
      attr_reader   :current_transaction
      attr_accessor :transaction_sample_builder

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

      # TT's and SQL
      attr_accessor :record_tt, :record_sql

      def is_transaction_traced?
        @record_tt != false
      end

      def is_sql_recorded?
        @record_sql != false
      end

      # Busy calculator
      attr_accessor :busy_entries

      # Sql Sampler Transaction Data
      attr_accessor :sql_sampler_transaction_data

      # Scope stack tracking from NewRelic::StatsEngine::Transactions
      # Should not be nil--this class manages its initialization and resetting
      attr_reader :traced_method_stack
    end
  end
end
