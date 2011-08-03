require 'new_relic/agent'
require 'new_relic/control'
module NewRelic
  module Agent

    class SqlSampler

      # Module defining methods stubbed out when the agent is disabled
      module Shim #:nodoc:
        def notice_scope_empty(*args); end
        def notice_first_scope_push(*args); end
        def notice_transaction(*args); end
      end

      attr_reader :disabled
      
      # this is for unit tests only
      attr_reader :sql_traces

      def initialize

        config = NewRelic::Control.instance
        sampler_config = config.fetch('transaction_tracer', {})
        @explain_threshold = sampler_config.fetch('explain_threshold', 0.5).to_f
#        @stack_trace_threshold = sampler_config.fetch('stack_trace_threshold', 0.500).to_f
        @sql_traces = {}
        clear_transaction_data

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
      
      def notice_transaction(path, uri=nil, params={})
        transaction_data.set_transaction_info(path, uri, params) if !disabled && transaction_data
      end
      
      def notice_first_scope_push(time)
        create_transaction_data
      end
      
      def create_transaction_data
        Thread.current[:new_relic_sql_data] = TransactionSqlData.new
      end
      
      def transaction_data
        Thread.current[:new_relic_sql_data]
      end
      
      def clear_transaction_data
        Thread.current[:new_relic_sql_data] = nil
      end


      # This is called when we are done with the transaction.
      def notice_scope_empty(time=Time.now)
        data = transaction_data
        clear_transaction_data
        
        if data.sql_data.count > 0
          @samples_lock.synchronize do
            NewRelic::Agent.instance.log.debug "Harvesting #{data.sql_data.count} slow transaction sql statement(s)"
            #FIXME get tx name and uri
            harvest_slow_sql data
          end
        end
      end
      
      # this should always be called under the @samples_lock
      def harvest_slow_sql(transaction_sql_data)
        transaction_sql_data.sql_data.each do |sql_item|
          obfuscated_sql = NewRelic::Agent.instance.send(:default_sql_obfuscator, sql_item.sql)
          sql_trace = @sql_traces[obfuscated_sql]
          if sql_trace
            sql_trace.aggregate sql_item, transaction_sql_data.path, transaction_sql_data.uri
          else
            @sql_traces[obfuscated_sql] = SqlTrace.new(obfuscated_sql, sql_item, transaction_sql_data.path, transaction_sql_data.uri)
          end
        end

      end

      def notice_sql(sql, metric_name, config, duration)
        return unless transaction_data
        if NewRelic::Agent.is_sql_recorded?
          if duration > @explain_threshold
            backtrace = caller.join("\n")
            transaction_data.sql_data << SlowSql.new(sql, metric_name, duration, backtrace)
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
        
        #FIXME obfuscate sql if necessary
        
        result.sort{|a,b| b.max_call_time <=> a.max_call_time}[0,20]
      end

      # reset samples without rebooting the web server
      def reset!
      end

      private

    end
    
    class TransactionSqlData
      attr_reader :path
      attr_reader :uri
      attr_reader :params
      attr_reader :sql_data
      
      def initialize
        @sql_data = []
      end
      
      def set_transaction_info(path, uri, params)
        @path = path
        @uri = uri
        @params = params
      end
    end
    
    class SlowSql
      attr_reader :sql
      attr_reader :metric_name
      attr_reader :duration
      attr_reader :backtrace
      
      def initialize(sql, metric_name, duration, backtrace = nil)
        @sql = sql
        @metric_name = metric_name
        @duration = duration
        @backtrace = backtrace
      end
    end
    
    class SqlTrace
      attr_reader :path
      attr_reader :url
      attr_reader :sql_id
      attr_reader :sql
      attr_reader :database_metric_name

      attr_reader :call_count
      attr_reader :total_call_time
      attr_reader :min_call_time
      attr_reader :max_call_time

      attr_reader :params

      attr_reader :stats

      def initialize(obfuscated_sql, slow_sql, path, uri)
        @params = {} #FIXME
        @sql_id = obfuscated_sql.hash
        set_primary slow_sql, path, uri

        @stats = MethodTraceStats.new
        record_data_point slow_sql.duration
      end

      def set_primary(slow_sql, path, uri)
        @sql = slow_sql.sql
        @database_metric_name = slow_sql.metric_name
        @path = path
        @url = uri
        # FIXME
        @params[:backtrace] = slow_sql.backtrace if slow_sql.backtrace
      end
      
      def aggregate(slow_sql, path, uri)
        if slow_sql.duration > @stats.max_call_time
          set_primary slow_sql, path, uri
        end

        record_data_point slow_sql.duration
      end

      def record_data_point(duration)
        @stats.record_data_point duration

        @call_count = @stats.call_count
        @total_call_time = @stats.total_call_time
        @min_call_time = @stats.min_call_time
        @max_call_time = @stats.max_call_time
      end
      
      def to_json(*a)
        [@path, @url, @sql_id, @sql, @database_metric_name, @call_count, @total_call_time, @min_call_time, @max_call_time, @params].to_json(*a)
      end
    end
  end
end
