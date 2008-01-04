require 'newrelic/stats'
require 'newrelic/metric_data'
require 'logger'

module NewRelic::Agent
  class StatsEngine
    POLL_PERIOD = 1
    
    attr_reader :log
    
    class SampledItem
      def initialize(stats, &callback)
        @stats = stats
        @callback = callback
      end
      
      def poll
        @callback.call @stats
      end
    end
    
    def initialize(log = Logger.new(STDOUT))
      @stats_hash = {}
      @sampled_items = []
      @scope_stack_listeners = []
      @log = log
      
      # start up a thread that will periodically poll for metric samples
      @sampler_thread = Thread.new do
        while true do
          begin
            sleep POLL_PERIOD
            @sampled_items.each do |sampled_item|
              sampled_item.poll
            end
          rescue Exception => e
            log.error e
            log.debug e.backtrace.to_s
          end
        end
      end
    end
    
    def add_scope_stack_listener(l)
      @scope_stack_listeners << l
    end
    
    def push_scope(scope)
      @scope_stack_listeners.each do |l|
        l.notice_first_scope_push if scope_stack.empty? 
        l.notice_push_scope scope
      end
      
      scope_stack.push scope
    end
    
    def pop_scope
      scope = scope_stack.pop
      
      @scope_stack_listeners.each do |l|
        l.notice_pop_scope scope
        l.notice_scope_empty if scope_stack.empty? 
      end
    end
    
    def peek_scope
      scope_stack.last
    end
    
    def add_sampled_metric(metric_name, &sampler_callback)
      stats = get_stats(metric_name, false)
      @sampled_items << SampledItem.new(stats, &sampler_callback)
    end
    
    def get_stats(metric_name, use_scope = true)
      scope = peek_scope
      
      spec = NewRelic::MetricSpec.new metric_name
      stats = @stats_hash[spec]
      if stats.nil?
        stats = NewRelic::MethodTraceStats.new
        @stats_hash[spec] = stats
      end
      
      if scope && use_scope
        spec = NewRelic::MetricSpec.new metric_name, scope
        
        scoped_stats = @stats_hash[spec]
        if scoped_stats.nil?
          scoped_stats = NewRelic::ScopedMethodTraceStats.new stats
          @stats_hash[spec] = scoped_stats        
        end
        
        stats = scoped_stats
      end
      return stats
    end
    
    def harvest_timeslice_data(previous_timeslice_data, metric_ids)
      timeslice_data = {}
      
      @stats_hash.keys.each do |metric_spec|
        
        # get a copy of the stats collected since the last harvest, and clear
        # the stats inside our hash table for the next time slice.
        stats = @stats_hash[metric_spec]
        stats_copy = stats.clone
        stats.reset
        
        # if the previous timeslice data has not been reported (due to an error of some sort)
        # then we need to merge this timeslice with the previously accumulated - but not sent
        # data
        previous_metric_data = previous_timeslice_data[metric_spec]
        stats_copy.merge! previous_metric_data.stats unless previous_metric_data.nil?
        
        # don't bother collecting and reporting stats that have zero-values for this timeslice.
        # significant performance boost and storage savings.
        unless stats_copy.call_count == 0
          metric_data = NewRelic::MetricData.new(metric_spec, stats_copy, metric_ids[metric_spec])
          
          timeslice_data[metric_spec] = metric_data
        end
      end
      
      timeslice_data
    end
    
    private
    
      def scope_stack
        s = Thread::current[:scope_stack]
        if s.nil?
          s = []
          Thread::current[:scope_stack] = s
        end
        s
      end
  end
end