# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
module Agent
  class StatsEngine
    # A simple stack element that tracks the current name and length
    # of the executing stack
    class ScopeStackElement
      attr_reader :deduct_call_time_from_parent, :tag
      attr_accessor :name, :start_time, :children_time
      def initialize(tag, start_time, deduct_call_time)
        @tag = tag
        @start_time = start_time
        @deduct_call_time_from_parent = deduct_call_time
        @children_time = 0
      end
    end

    # Handles pushing and popping elements onto an internal stack that
    # tracks where time should be allocated in Transaction Traces
    module Transactions

      # Defines methods that stub out the stats engine methods
      # when the agent is disabled
      module Shim # :nodoc:
        def start_transaction(*args); end
        def end_transaction; end
        def push_scope(*args); end
        def transaction_sampler=(*args); end
        def pop_scope(*args); end
      end


      # Pushes a scope onto the transaction stack - this generates a
      # TransactionSample::Segment at the end of transaction execution
      # The generated segment will not be named until the corresponding
      # pop_scope call is made.
      # +tag+ should be a Symbol, and is only used for debugging purposes to
      # identify this scope if the stack gets corrupted.
      def push_scope(tag, time = Time.now.to_f, deduct_call_time_from_parent = true)
        stack = scope_stack
        transaction_sampler.notice_push_scope(time) if sampler_enabled?
        scope = ScopeStackElement.new(tag, time, deduct_call_time_from_parent)
        stack.push scope
        scope
      end

      # Pops a scope off the transaction stack - this updates the
      # transaction sampler that we've finished execution of a traced method
      # +expected_scope+ should be the ScopeStackElement that was returned by
      # the corresponding push_scope call.
      # +name+ is the name that will be applied to the generated transaction
      # trace segment.
      def pop_scope(expected_scope, name, time=Time.now.to_f)
        stack = scope_stack
        scope = stack.pop
        fail "unbalanced pop from blame stack, got #{scope ? scope.tag : 'nil'}, expected #{expected_scope ? expected_scope.tag : 'nil'}" if scope != expected_scope

        if !stack.empty?
          if scope.deduct_call_time_from_parent
            stack.last.children_time += (time - scope.start_time)
          else
            stack.last.children_time += scope.children_time
          end
        end
        transaction_sampler.notice_pop_scope(name, time) if sampler_enabled?
        scope.name = name
        scope
      end

      def sampler_enabled?
        Agent.config[:'transaction_tracer.enabled'] || Agent.config[:developer_mode]
      end

      def transaction_sampler
        Agent.instance.transaction_sampler
      end

      # deprecated--used to add transaction sampler, now we always look to the agent
      def transaction_sampler= sampler
        NewRelic::Agent.logger.warn("NewRelic::Agent::StatsEngine#transaction_sampler is deprecated")
      end

      # Start a new transaction, unless one is already in progress
      def start_transaction
        NewRelic::Agent.instance.events.notify(:start_transaction)
      end

      # Try to clean up gracefully, otherwise we leave things hanging around on thread locals.
      # If it looks like a transaction is still in progress, then maybe this is an inner transaction
      # and is ignored.
      #
      def end_transaction
        stack = scope_stack

        if stack && stack.empty?
          NewRelic::Agent::TransactionState.get.clear_stats_scope_stack
        end
      end

      def transaction_stats_hash
        Transaction.current && Transaction.current.stats_hash
      end

      # Returns the current scope stack, memoized to a thread local variable
      def scope_stack
        NewRelic::Agent::TransactionState.get.stats_scope_stack
      end
    end
  end
end
end
