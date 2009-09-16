module NewRelic::Agent
  class StatsEngine
    
    module Shim # :nodoc:
      def start_transaction; end
      def end_transaction; end
      def push_scope(*args); end
      def pop_scope(*args); end
    end
    
    # Defines methods that stub out the stats engine methods
    # when the agent is disabled
    
    class ScopeStackElement
      attr_reader :name, :deduct_call_time_from_parent
      attr_accessor :children_time
      def initialize(name, deduct_call_time)
        @name = name
        @deduct_call_time_from_parent = deduct_call_time
        @children_time = 0
      end
    end
    
    module Transactions
      
      def transaction_sampler= sampler
        fail "Can't add a scope listener midflight in a transaction" if scope_stack.any?
        @transaction_sampler = sampler
      end
      
      def remove_transaction_sampler(l)
        @transaction_sampler = nil
      end
      
      def push_scope(metric, time = Time.now.to_f, deduct_call_time_from_parent = true)
        
        stack = scope_stack
        if collecting_gc?
          if stack.empty?
            # reset the gc time so we only include gc time spent during this call
            @last_gc_timestamp = GC.time
            @last_gc_count = GC.collections
          else
            capture_gc_time
          end
        end
        if @transaction_sampler
          @transaction_sampler.notice_first_scope_push(time) if stack.empty? 
          @transaction_sampler.notice_push_scope metric, time
        end
        scope = ScopeStackElement.new(metric, deduct_call_time_from_parent)
        stack.push scope
        scope
      end
      
      def pop_scope(expected_scope, duration, time=Time.now.to_f)
        capture_gc_time if collecting_gc?
        stack = scope_stack
        scope = stack.pop
        
        fail "unbalanced pop from blame stack: #{scope.name} != #{expected_scope.name}" if scope != expected_scope
        
        if !stack.empty? 
          if scope.deduct_call_time_from_parent
            stack.last.children_time += duration
          else
            stack.last.children_time += scope.children_time
          end
        end
        
        if @transaction_sampler
          @transaction_sampler.notice_pop_scope(scope.name, time)
          @transaction_sampler.notice_scope_empty(time) if stack.empty? 
        end
        scope
      end
      
      def peek_scope
        scope_stack.last
      end
      
      # set the name of the transaction for the current thread, which will be used
      # to define the scope of all traced methods called on this thread until the
      # scope stack is empty.  
      #
      # currently the transaction name is the name of the controller action that 
      # is invoked via the dispatcher, but conceivably we could use other transaction
      # names in the future if the traced application does more than service http request
      # via controller actions
      def transaction_name=(transaction)
        Thread::current[:newrelic_transaction_name] = transaction
      end
      
      def transaction_name
        Thread::current[:newrelic_transaction_name]
      end
      
      def start_transaction
        Thread::current[:newrelic_scope_stack] = []
      end
      
      # Try to clean up gracefully, otherwise we leave things hanging around on thread locals
      #
      def end_transaction
        stack = scope_stack
        
        if stack
          @transaction_sampler.notice_scope_empty(Time.now) if @transaction_sampler && !stack.empty? 
          Thread::current[:newrelic_scope_stack] = nil
        end
        
        Thread::current[:newrelic_transaction_name] = nil
      end
      
      private
      
      @@collecting_gc = GC.respond_to?(:time) && GC.respond_to?(:collections) 
      # Make sure we don't do this in a multi-threaded environment
      def collecting_gc?
        @@collecting_gc
      end
      
      # Assumes collecting_gc?
      def capture_gc_time
        # Skip this if we are already in this segment
        return if !scope_stack.empty? && scope_stack.last.name == "GC/cumulative"
        num_calls = GC.collections - @last_gc_count
        elapsed = (GC.time - @last_gc_timestamp)/1000000.0 
        if num_calls > 0
          @last_gc_timestamp += elapsed
          @last_gc_count += num_calls
          # Allocate the GC time to a scope as if the GC just ended
          # right now.
          time = Time.now.to_f
          gc_scope = push_scope("GC/cumulative", time - elapsed)
          # GC stats are collected into a blamed metric which allows
          # us to show the stats controller by controller
          gc_stats = NewRelic::Agent.get_stats(gc_scope.name, true)  
          gc_stats.record_multiple_data_points(elapsed, num_calls)
          pop_scope(gc_scope, time)
        end
      end
      
      def scope_stack
        Thread::current[:newrelic_scope_stack] ||= []
      end
      
    end
  end
end
