# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    # This is THE location to store thread local information during a transaction
    # Need a new piece of data? Add a method here, NOT a new thread local variable.
    class TransactionState

      def self.get
        Thread.current[:newrelic_transaction_state] ||= TransactionState.new
      end

      def self.clear
        Thread.current[:newrelic_transaction_state] = nil
      end

      # Cross app tracing
      #
      # Because we aren't in the right spot when our transaction actually
      # starts, hold client_cross_app_id and referring transaction guid info
      # on thread local until then.
      attr_accessor :client_cross_app_id, :referring_transaction_info

      # Execution tracing on current thread
      attr_accessor :untraced

      def push_traced(should_trace)
        @untraced ||= []
        @untraced << should_trace
      end

      def pop_traced
        @untraced.pop if @untraced
      end

      def is_traced?
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
    end
  end
end
