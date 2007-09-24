require 'seldon/transaction_sample'
require 'thread'

module Seldon::Agent
  class TransactionSampler
    def initialize(agent = nil)
      @rules = []
      @samples = []
      @mutex = Mutex.new
      
      # when the agent is nil, we are in a unit test.
      # don't hook into the stats engine, which owns
      # the scope stack
      unless agent.nil?
        agent.stats_engine.add_scope_stack_listener self
      end
    end
    
    def add_rule(rule)
      @mutex.synchronize do 
        @rules << rule
      end
    end
    
    def notice_first_scope_push
      get_or_create_builder
    end
    
    def notice_push_scope(scope)
      builder = get_builder
      return if builder.nil?
      
      check_rules(scope)
      builder.trace_entry(scope)
    end
  
    def notice_pop_scope(scope)
      builder = get_builder
      return if builder.nil?
      
      builder.trace_exit(scope)
    end
    
    def notice_scope_empty
      builder = get_builder
      return if builder.nil?
      
      builder.finish_trace
      
      @mutex.synchronize do
        @samples << builder.sample if get_should_collect_sample
        
        # remove any rules that have expired
        @rules.reject!{ |rule| rule.has_expired? }
      end
      
      reset_builder
    end
    
    def harvest_samples(previous_samples=[])
      @mutex.synchronize do 
        s = previous_samples
      
        @samples.each do |sample|
          s << sample
        end
        @samples = []
        s
      end
    end
    
    private 
      def check_rules(scope)
        return if get_should_collect_sample
        @rules.each do |rule|
          if rule.check(scope)
            set_should_collect_sample
          end
        end
      end
    
      BUILDER_KEY = :transaction_sample_builder
      def get_or_create_builder
        return nil if @rules.empty?
        
        builder = get_builder
        if builder.nil?
          builder = TransactionSampleBuilder.new
          Thread::current[BUILDER_KEY] = builder
        end
        
        builder
      end
      
      def get_builder
        Thread::current[BUILDER_KEY]
      end
      
      def reset_builder
        Thread::current[BUILDER_KEY] = nil
        set_should_collect_sample(false)
      end
      
      COLLECT_SAMPLE_KEY = :should_collect_sample
      def get_should_collect_sample
        Thread::current[COLLECT_SAMPLE_KEY]
      end
      
      def set_should_collect_sample(value=true)
        Thread::current[COLLECT_SAMPLE_KEY] = value
      end
  end

  # a builder is created with every sampled transaction, to dynamically
  # generate the sampled data
  class TransactionSampleBuilder
    
    def initialize
      @sample = Seldon::TransactionSample.new
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
    end
    
    def freeze
      @sample.freeze unless sample.frozen?
    end
    
    def relative_timestamp
      Time.now - @sample.start_time
    end
    
    def sample
      fail "Not finished building" unless @sample.frozen?
      @sample
    end
    
  end
end