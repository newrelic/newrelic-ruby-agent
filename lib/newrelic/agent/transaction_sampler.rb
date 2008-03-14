require 'newrelic/transaction_sample'
require 'thread'

module NewRelic::Agent
  class TransactionSampler
    def initialize(agent = nil, max_samples = 500)
      @samples = []
      @mutex = Mutex.new
      @max_samples = max_samples

      # when the agent is nil, we are in a unit test.
      # don't hook into the stats engine, which owns
      # the scope stack
      unless agent.nil?
        agent.stats_engine.add_scope_stack_listener self
      end
    end
    
    
    def notice_first_scope_push
      get_or_create_builder
    end
    
    def notice_push_scope(scope)
      with_builder do |builder|
        check_rules(scope)      # TODO no longer necessary once we confirm overhead
        builder.trace_entry(scope)
        
        # in developer mode, capture the stack trace with the segment.
        # this is cpu and memory expensive and therefore should not be
        # turned on in production mode
        if ::RPM_DEVELOPER
          segment = builder.current_segment
          if segment
            # NOTE we manually inspect stack traces to determine that the 
            # agent consumes the last 8 frames.  Review after we make changes
            # to transaction sampling or stats engine to make sure this remains
            # a true assumption
            trace = caller(8)
            
            trace = trace[0..40] if trace.length > 40
            segment[:backtrace] = trace
          end
        end
      end
    end
  
    def notice_pop_scope(scope)
      with_builder do |builder|
        builder.trace_exit(scope)
      end
    end
    
    def notice_scope_empty
      with_builder do |builder|
        builder.finish_trace
      
        @mutex.synchronize do
          sample = builder.sample
        
          # ensure we don't collect more than a specified number of samples in memory
          # TODO don't keep in memory for production mode; just keep the @slowest_sample
          @samples << sample if should_collect_sample?
          @samples.shift while @samples.length > @max_samples
          
          if @slowest_sample.nil? || @slowest_sample.duration < sample.duration
            @slowest_sample = sample
          end
        end
      
        reset_builder
      end
    end
    
    def notice_transaction(path, request, params)
      with_builder do |builder|
        builder.set_transaction_info(path, request, params)
      end
    end
    
    def notice_sql(sql)
      with_builder do |builder|
        segment = builder.current_segment
        if segment
          current_sql = segment[:sql]
          sql = current_sql + ";\n" + sql if current_sql
          segment[:sql] = sql
        end
      end
    end
    
    # get the set of collected samples, merging into previous samples,
    # and clear the collected sample list. 
    # TODO remove me, and replace with 'harvest_slowest_sample'.  Remove
    # the @samples array in production mode, too.
    def harvest_samples(previous_samples=[])
      @mutex.synchronize do 
        s = previous_samples
        
        @samples.each do |sample|
          s << sample
        end
        @samples = [] unless is_developer_mode?
        s
      end
    end
    
    def harvest_slowest_sample(previous_slowest = nil)
      slowest = @slowest_sample
      @slowest_sample = nil
      
      if previous_slowest.nil? || previous_slowest.duration < slowest.duration
        slowest
      else
        previous_slowest
      end
    end

    # get the list of samples without clearing the list.
    def get_samples
      @mutex.synchronize do
        return @samples.clone
      end
    end
    
    private 
      # TODO all of this goes away once we confirm that we can always measure samples
      # at acceptable overhead.  Don't check rules, and remove shold_colelct_sample?
      def check_rules(scope)
        return if should_collect_sample?
        set_should_collect_sample and return #if is_developer_mode?
      end
    
      BUILDER_KEY = :transaction_sample_builder
      def get_or_create_builder
        # Commenting out - see above.  We will leave sampling on all the time.
#        return nil if @rules.empty? && !is_developer_mode?
        
        builder = get_builder
        if builder.nil?
          builder = TransactionSampleBuilder.new
          Thread::current[BUILDER_KEY] = builder
        end
        
        builder
      end
      
      # most entry points into the transaction sampler take the current transaction
      # sample builder and do something with it.  There may or may not be a current
      # transaction sample builder on this thread. If none is present, the provided
      # block is not called (saving sampling overhead); if one is, then the 
      # block is called with the transaction sample builder that is registered
      # with this thread.
      def with_builder
        builder = get_builder
        yield builder if builder
      end
      
      def get_builder
        Thread::current[BUILDER_KEY]
      end
      
      def reset_builder
        Thread::current[BUILDER_KEY] = nil
        set_should_collect_sample(false)
      end
      
      COLLECT_SAMPLE_KEY = :should_collect_sample
      def should_collect_sample?
        Thread::current[COLLECT_SAMPLE_KEY]
      end
      
      def set_should_collect_sample(value=true)
        Thread::current[COLLECT_SAMPLE_KEY] = value
      end
      
      def is_developer_mode?
        @developer_mode ||= (defined?(::RPM_DEVELOPER) && ::RPM_DEVELOPER)
      end
  end

  # a builder is created with every sampled transaction, to dynamically
  # generate the sampled data
  class TransactionSampleBuilder
    attr_reader :current_segment
    
    def initialize
      @sample = NewRelic::TransactionSample.new
      @sample.begin_building
      @current_segment = @sample.root_segment
    end

    def trace_entry(metric_name)
      segment = @sample.create_segment(relative_timestamp, metric_name)
      @current_segment.add_called_segment(segment)
      @current_segment = segment
    end

    def trace_exit(metric_name)
      if metric_name != @current_segment.metric_name
        fail "unbalanced entry/exit: #{metric_name} != #{@current_segment.metric_name}"
      end
      
      @current_segment.end_trace relative_timestamp
      @current_segment = @current_segment.parent_segment
    end
    
    def finish_trace
      @sample.root_segment.end_trace relative_timestamp
      @sample.freeze
      @current_segment = nil
    end
    
    def freeze
      @sample.freeze unless sample.frozen?
    end
    
    def relative_timestamp
      Time.now - @sample.start_time
    end
    
    def set_transaction_info(path, request, params)
      @sample.params.merge!(params)
      @sample.params[:path] = path
      @sample.params[:uri] = request.path if request
    end
    
    def sample
      fail "Not finished building" unless @sample.frozen?
      @sample
    end
    
  end
end