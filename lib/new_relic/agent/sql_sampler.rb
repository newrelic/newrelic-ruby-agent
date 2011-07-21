require 'new_relic/agent'
require 'new_relic/control'
module NewRelic
  module Agent

    class SqlSampler

      # Module defining methods stubbed out when the agent is disabled
      module Shim #:nodoc:
        def notice_scope_empty(*args); end
        def notice_first_scope_push(*args); end
      end

      attr_reader :disabled
      
      # this is for unit tests only
      attr_reader :sql_traces

      def initialize

        config = NewRelic::Control.instance
        sampler_config = config.fetch('transaction_tracer', {})
        @explain_threshold = sampler_config.fetch('explain_threshold', 0.5).to_f
        @sql_traces = {}
        Thread.current[:transaction_sql] = nil

        # This lock is used to synchronize access to the @last_sample
        # and related variables. It can become necessary on JRuby or
        # any 'honest-to-god'-multithreaded system
        @samples_lock = Mutex.new
      end

      # Enable the sql sampler - this also registers it with
      # the statistics engine.
      def enable
        @disabled = false
        NewRelic::Agent.instance.stats_engine.sql_sampler = self
      end

      # Disable the sql sampler - this also deregisters it
      # with the statistics engine.
      def disable
        @disabled = true
        NewRelic::Agent.instance.stats_engine.remove_sql_sampler(self)
      end

      def notice_first_scope_push(time)
        Thread.current[:transaction_sql] = []
      end


      # This is called when we are done with the transaction.
      def notice_scope_empty(time=Time.now)
        slow_sql = Thread.current[:transaction_sql]
        Thread.current[:transaction_sql] = nil
        
        if slow_sql.count > 0
          @samples_lock.synchronize do
            NewRelic::Agent.instance.log.debug "Harvesting #{slow_sql.count} slow transaction sql statement(s)"
            #FIXME get tx name and uri
            harvest_slow_sql "", "", slow_sql
          end
        end
      end
      
      # this should always be called under the @samples_lock
      def harvest_slow_sql(transaction_name, uri, slow_sql)
        slow_sql.each do |sql_item|
          obfuscated_sql = NewRelic::Agent.instance.send(:default_sql_obfuscator, sql_item.sql)
          sql_trace = @sql_traces[obfuscated_sql]
          if sql_trace
            sql_trace.aggregate sql_item, transaction_name, uri
          else
            @sql_traces[obfuscated_sql] = SqlTrace.new(obfuscated_sql, sql_item, transaction_name, uri)
          end
        end

      end

      def notice_sql(sql, metric_name, config, duration)
        if NewRelic::Agent.is_sql_recorded? && Thread.current[:transaction_sql]
          if duration > @explain_threshold
            Thread.current[:transaction_sql] << SlowSql.new(sql, metric_name, duration)
          end
        end
      end

      def merge(sql_traces)
        @samples_lock.synchronize do
#FIXME we need to merge the sql_traces array back into the @sql_traces hash
#          @sql_traces.merge! sql_traces
        end
      end

      def harvest
        return [] if disabled
        result = []
        @samples_lock.synchronize do
          result = @sql_traces.values
          @sql_traces = {}
        end
        
        #FIXME sort on max duration, trim list
        
        #FIXME obfuscate sql if necessary
        result
      end

      # reset samples without rebooting the web server
      def reset!
      end

      private

    end
    
    class SlowSql
      attr_reader :sql
      attr_reader :metric_name
      attr_reader :duration
      
      def initialize(sql, metric_name, duration)
        @sql = sql
        @metric_name = metric_name
        @duration = duration
      end
    end
    
    class SqlTrace
      attr_reader :sql_id
      attr_reader :sql
      attr_reader :metric_name
      attr_reader :stats
      attr_reader :transaction_name
      attr_reader :uri
      
      def initialize(obfuscated_sql, slow_sql, transaction_name, uri)
        @sql_id = obfuscated_sql.hash
        set_primary slow_sql, transaction_name, uri
        @stats = MethodTraceStats.new
        @stats.record_data_point slow_sql.duration
        @parameters = {} #FIXME
#        @duration = slow_sql.duration
      end
      
      def set_primary(slow_sql, transaction_name, uri)
        @sql = slow_sql.sql
        @metric_name = slow_sql.metric_name
        @transaction_name = transaction_name
        @uri = uri
      end
      
      def aggregate(slow_sql, transaction_name, uri)
        if slow_sql.duration > @stats.max_call_time
          set_primary slow_sql, transaction_name, uri
        end
        
        @stats.record_data_point slow_sql.duration
      end
      
      def to_json(*a)
        [@transaction_name, @uri, @sql_id, @sql, @metric_name, @stats.call_count, @stats.total_call_time, @stats.min_call_time, @stats.max_call_time, @parameters].to_json(*a)
      end
      
      # these methods are for the server side aggregator
      def call_count
        @stats.call_count
      end
      
      def total_call_time
        @stats.total_call_time
      end
      
      def min_call_time
        @stats.min_call_time
      end
      
      def max_call_time
        @stats.max_call_time
      end
    end
  end
end
