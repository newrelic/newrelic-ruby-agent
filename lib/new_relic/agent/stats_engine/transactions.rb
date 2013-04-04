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
        def scope_name=(*args); end
        def scope_name; end
        def pop_scope(*args); end
      end

      attr_reader :transaction_sampler

      # add a new transaction sampler, unless we're currently in a
      # transaction (then we fail)
      def transaction_sampler= sampler
        fail "Can't add a scope listener midflight in a transaction" if scope_stack.any?
        @transaction_sampler = sampler
      end

      # removes a transaction sampler
      def remove_transaction_sampler(l)
        @transaction_sampler = nil
      end

      # Pushes a scope onto the transaction stack - this generates a
      # TransactionSample::Segment at the end of transaction execution
      # The generated segment will not be named until the corresponding
      # pop_scope call is made.
      # +tag+ should be a Symbol, and is only used for debugging purposes to
      # identify this scope if the stack gets corrupted.
      def push_scope(tag, time = Time.now.to_f, deduct_call_time_from_parent = true)
        stack = scope_stack
        @transaction_sampler.notice_push_scope(time) if sampler_enabled?
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
        @transaction_sampler.notice_pop_scope(name, time) if sampler_enabled?
        scope.name = name
        scope
      end

      def sampler_enabled?
        @transaction_sampler && Agent.config[:'transaction_tracer.enabled']
      end

      # set the name of the transaction for the current thread, which will be used
      # to define the scope of all traced methods called on this thread until the
      # scope stack is empty.
      #
      # currently the transaction name is the name of the controller action that
      # is invoked via the dispatcher, but conceivably we could use other transaction
      # names in the future if the traced application does more than service http request
      # via controller actions
      def scope_name=(transaction)
        Thread::current[:newrelic_scope_name] = transaction
      end

      # Returns the current scope name from the thread local
      def scope_name
        Thread::current[:newrelic_scope_name]
      end

      # Start a new transaction, unless one is already in progress
      # RUBY-1059: this doesn't take an arg anymore
      def start_transaction(name=nil)
        NewRelic::Agent.instance.events.notify(:start_transaction)
        GCProfiler.init
      end

      # Try to clean up gracefully, otherwise we leave things hanging around on thread locals.
      # If it looks like a transaction is still in progress, then maybe this is an inner transaction
      # and is ignored.
      #
      def end_transaction(name=nil)
        stack = scope_stack

        if stack && stack.empty?
          Thread::current[:newrelic_scope_stack] = nil
          Thread::current[:newrelic_scope_name] = nil
        end
      end

      def record_gc_time
        elapsed = GCProfiler.capture
        if @transaction_sampler && @transaction_sampler.last_sample
          @transaction_sampler.last_sample.params[:custom_params] ||= {}
          @transaction_sampler.last_sample.params[:custom_params][:gc_time] = elapsed
        end
      end

      def transaction_stats_hash
        transaction_stats_stack.last
      end

      def push_transaction_stats
        transaction_stats_stack << StatsHash.new
      end

      def pop_transaction_stats(transaction_name)
        # RUBY-1059: This should not use TransactionInfo
        Thread::current[:newrelic_scope_stack] ||= []
        self.scope_name = transaction_name # RUBY-1059 - maybe not necessary
        stats = transaction_stats_stack.pop
        merge!(apply_scopes(stats, transaction_name)) if stats
        stats
      end

      def apply_scopes(stats_hash, resolved_name)
        new_stats = StatsHash.new
        stats_hash.each do |spec, stats|
          if spec.scope != '' &&
              spec.scope.to_sym == StatsEngine::SCOPE_PLACEHOLDER
            spec.scope = resolved_name
          end
          new_stats[spec] = stats
        end
        return new_stats
      end

      # Returns the current scope stack, memoized to a thread local variable
      def scope_stack
        Thread::current[:newrelic_scope_stack] ||= []
      end

      def transaction_stats_stack
        Thread.current[:newrelic_transaction_stack] ||= []
      end
    end
  end
end
end
