
module NewRelic::Agent
  class StatsEngine
    POLL_PERIOD = 10
    
    ScopeStackElement = Struct.new(:name, :children_time, :deduct_call_time_from_parent)
    
    def initialize
      @stats_hash = {}
      @harvest_samplers = []
      @periodic_samplers = []
      @scope_stack_listener = nil
      
      # Makes the unit tests happy
      Thread::current[:newrelic_scope_stack] = nil
      
      spawn_sampler_thread
    end

    def log
      NewRelic::Control.instance.log
    end
    
    def spawn_sampler_thread
      
      return if !@sampler_process.nil? && @sampler_process == $$ 
      
      # start up a thread that will periodically poll for metric samples
      @sampler_thread = Thread.new do
        while true do
          begin
            sleep POLL_PERIOD
            poll @periodic_samplers
          end
        end
      end
      @sampler_thread['newrelic_label'] = 'Sampler Tasks'
      @sampler_process = $$
    end
    
    def add_scope_stack_listener(l)
      fail "Can't add a scope listener midflight in a transaction" if scope_stack.any?
      @scope_stack_listener =  l
    end
    
    def remove_scope_stack_listener(l)
      @scope_stack_listener = nil
    end
    
    def push_scope(metric, time = Time.now.to_f, deduct_call_time_from_parent = true)
      
      stack = (Thread::current[:newrelic_scope_stack] ||= [])
      
      if @scope_stack_listener
        @scope_stack_listener.notice_first_scope_push(time) if stack.empty? 
        @scope_stack_listener.notice_push_scope metric, time
      end
      
      scope = ScopeStackElement.new(metric, 0, deduct_call_time_from_parent)
      stack.push scope
      
      scope
    end
    
    def pop_scope(expected_scope, duration, time=Time.now.to_f)

      stack = Thread::current[:newrelic_scope_stack]
      
      scope = stack.pop
      
      fail "unbalanced pop from blame stack: #{scope.name} != #{expected_scope.name}" if scope != expected_scope
       
      stack.last.children_time += duration unless (stack.empty? || !scope.deduct_call_time_from_parent)
      
      if !scope.deduct_call_time_from_parent && !stack.empty?
        stack.last.children_time += scope.children_time
      end
      
      if @scope_stack_listener
        @scope_stack_listener.notice_pop_scope(scope.name, time)
        @scope_stack_listener.notice_scope_empty(time) if stack.empty? 
      end
      
      scope
    end
    
    def peek_scope
      scope_stack.last
    end
    
    # Add an instance of Sampler to be invoked about every 10 seconds on a background
    # thread.
    def add_sampler sampler
      @periodic_samplers << sampler
      sampler.stats_engine = self
      log.debug "Adding sampler #{sampler.id.to_s}"
    end
    
    # Add a sampler to be invoked just before each harvest.
    def add_harvest_sampler sampler
      @harvest_samplers << sampler
      sampler.stats_engine = self
      log.debug "Adding harvest time sampler: #{sampler.id.to_s}"
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
    
    
    def lookup_stat(metric_name)
      return @stats_hash[metric_name]
    end
    def metrics
      return @stats_hash.keys
    end
    
    def get_stats_no_scope(metric_name)
      stats = @stats_hash[metric_name]
      if stats.nil?
        stats = NewRelic::MethodTraceStats.new
        @stats_hash[metric_name] = stats
      end
      stats
    end
    
    # This version allows a caller to pass a stat class to use
    #
    def get_custom_stats(metric_name, stat_class)
      stats = @stats_hash[metric_name]
      if stats.nil?
        stats = stat_class.new
        @stats_hash[metric_name] = stats
      end
      stats
    end
    
    # If use_scope is true, two chained metrics are created, one with scope and one without
    # If scoped_metric_only is true, only a scoped metric is created (used by rendering metrics which by definition are per controller only)
    def get_stats(metric_name, use_scope = true, scoped_metric_only = false)
      
      if scoped_metric_only
        spec = NewRelic::MetricSpec.new metric_name, transaction_name
        
        stats = @stats_hash[spec]
        if stats.nil?
          stats = NewRelic::MethodTraceStats.new
          @stats_hash[spec] = stats        
        end
      else  
        stats = @stats_hash[metric_name]
        if stats.nil?
          stats = NewRelic::MethodTraceStats.new
          @stats_hash[metric_name] = stats
        end
        
        if use_scope && transaction_name
          spec = NewRelic::MetricSpec.new metric_name, transaction_name
          
          scoped_stats = @stats_hash[spec]
          if scoped_stats.nil?
            scoped_stats = NewRelic::ScopedMethodTraceStats.new stats
            @stats_hash[spec] = scoped_stats        
          end
          
          stats = scoped_stats
        end
      end
      
      stats
    end
    
    # Harvest the timeslice data.  First recombine current statss
    # with any previously
    # unsent metrics, clear out stats cache, and return the current
    # stats. 
    # ---
    # Note: this is not synchronized.  There is still some risk in this and
    # we will revisit later to see if we can make this more robust without
    # sacrificing efficiency.
    # +++
    def harvest_timeslice_data(previous_timeslice_data, metric_ids)
      timeslice_data = {}
      poll @harvest_samplers
      @stats_hash.keys.each do | metric_spec |
        
        
        # get a copy of the stats collected since the last harvest, and clear
        # the stats inside our hash table for the next time slice.
        stats = @stats_hash[metric_spec]

        # we have an optimization for unscoped metrics
        if !(metric_spec.is_a? NewRelic::MetricSpec)
          metric_spec = NewRelic::MetricSpec.new metric_spec
        end

        if stats.nil? 
          raise "Nil stats for #{metric_spec.name} (#{metric_spec.scope})"
        end
        
        stats_copy = stats.clone
        stats.reset
        
        # if the previous timeslice data has not been reported (due to an error of some sort)
        # then we need to merge this timeslice with the previously accumulated - but not sent
        # data
        previous_metric_data = previous_timeslice_data[metric_spec]
        stats_copy.merge! previous_metric_data.stats unless previous_metric_data.nil?
        
        stats_copy.round!
        
        # don't bother collecting and reporting stats that have zero-values for this timeslice.
        # significant performance boost and storage savings.
        unless stats_copy.is_reset?
          
          metric_spec_for_transport = (metric_ids[metric_spec].nil?) ? metric_spec : nil
          
          metric_data = NewRelic::MetricData.new(metric_spec_for_transport, stats_copy, metric_ids[metric_spec])
          
          timeslice_data[metric_spec] = metric_data
        end
      end
      
      timeslice_data
    end
    
    def start_transaction
      Thread::current[:newrelic_scope_stack] = []
    end
    
    # Try to clean up gracefully, otherwise we leave things hanging around on thread locals
    #
    def end_transaction
      stack = Thread::current[:newrelic_scope_stack]
      
      if stack
        @scope_stack_listener.notice_scope_empty(Time.now) if @scope_stack_listener && !stack.empty? 
        Thread::current[:newrelic_scope_stack] = nil
      end
      
      Thread::current[:newrelic_transaction_name] = nil
    end
    
    def clear_stats # :nodoc: for test code only
      @stats_hash.clear
    end
    private
    
    # Call poll on each of the samplers.  Remove
    # the sampler if it raises.
    def poll(samplers)
      samplers.delete_if do |sampled_item|
        begin 
          sampled_item.poll
          false # it's okay.  don't delete it.
        rescue => e
          log.error "Removing #{sampled_item} from list"
          log.error e
          log.debug e.backtrace.to_s
          true # remove the sampler
        end
      end
    end
    def scope_stack
      Thread::current[:newrelic_scope_stack] ||= []
    end
  end
end
