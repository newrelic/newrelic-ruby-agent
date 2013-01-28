require 'zlib'
require 'base64'
require 'digest/md5'

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
        @sql_traces = {}
        clear_transaction_data

        # This lock is used to synchronize access to the @last_sample
        # and related variables. It can become necessary on JRuby or
        # any 'honest-to-god'-multithreaded system
        @samples_lock = Mutex.new
      end

      def enabled?
        Agent.config[:'slow_sql.enabled'] &&
          (Agent.config[:'slow_sql.record_sql'] == 'raw' ||
           Agent.config[:'slow_sql.record_sql'] == 'obfuscated') &&
          Agent.config[:'transaction_tracer.enabled']
      end

      def notice_transaction(path, uri=nil, params={})
        if NewRelic::Agent.instance.transaction_sampler.builder
          guid = NewRelic::Agent.instance.transaction_sampler.builder.sample.guid
        end
        if Agent.config[:'slow_sql.enabled'] && transaction_data
          transaction_data.set_transaction_info(path, uri, params, guid)
        end
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

        if data.sql_data.size > 0
          @samples_lock.synchronize do
            ::NewRelic::Agent.logger.debug "Harvesting #{data.sql_data.size} slow transaction sql statement(s)"
            #FIXME get tx name and uri
            harvest_slow_sql data
          end
        end
      end

      # this should always be called under the @samples_lock
      def harvest_slow_sql(transaction_sql_data)
        transaction_sql_data.sql_data.each do |sql_item|
          normalized_sql = sql_item.normalize
          sql_trace = @sql_traces[normalized_sql]
          if sql_trace
            sql_trace.aggregate(sql_item, transaction_sql_data.path,
                                transaction_sql_data.uri)
          else
            @sql_traces[normalized_sql] = SqlTrace.new(normalized_sql,
                sql_item, transaction_sql_data.path, transaction_sql_data.uri)
          end
        end

      end

      def notice_sql(sql, metric_name, config, duration)
        return unless transaction_data
        if NewRelic::Agent.is_sql_recorded?
          if duration > Agent.config[:'slow_sql.explain_threshold']
            backtrace = caller.join("\n")
            transaction_data.sql_data << SlowSql.new(sql, metric_name, config,
                                                     duration, backtrace)
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
        return [] if !Agent.config[:'slow_sql.enabled']
        result = []
        @samples_lock.synchronize do
          result = @sql_traces.values
          @sql_traces = {}
        end
        slowest = result.sort{|a,b| b.max_call_time <=> a.max_call_time}[0,10]
        slowest.each {|trace| trace.prepare_to_send }
        slowest
      end

      # reset samples without rebooting the web server
      def reset!
      end
    end

    class TransactionSqlData
      attr_reader :path
      attr_reader :uri
      attr_reader :params
      attr_reader :sql_data
      attr_reader :guid

      def initialize
        @sql_data = []
      end

      def set_transaction_info(path, uri, params, guid)
        @path = path
        @uri = uri
        @params = params
        @guid = guid
      end
    end

    class SlowSql
      attr_reader :sql
      attr_reader :metric_name
      attr_reader :duration
      attr_reader :backtrace

      def initialize(sql, metric_name, config, duration, backtrace = nil)
        @sql = sql
        @metric_name = metric_name
        @config = config
        @duration = duration
        @backtrace = backtrace
      end

      def obfuscate
        NewRelic::Agent::Database.obfuscate_sql(@sql)
      end

      def normalize
        NewRelic::Agent::Database::Obfuscator.instance \
          .default_sql_obfuscator(@sql).gsub(/\?\s*\,\s*/, '').gsub(/\s/, '')
      end

      def explain
        NewRelic::Agent::Database.explain_sql(@sql, @config)
      end
    end

    class SqlTrace < MethodTraceStats
      attr_reader :path
      attr_reader :url
      attr_reader :sql_id
      attr_reader :sql
      attr_reader :database_metric_name
      attr_reader :params

      def initialize(normalized_query, slow_sql, path, uri)
        super()
        @params = {} #FIXME
        @sql_id = consistent_hash(normalized_query)
        set_primary slow_sql, path, uri
        record_data_point slow_sql.duration
      end

      def set_primary(slow_sql, path, uri)
        @slow_sql = slow_sql
        @sql = slow_sql.sql
        @database_metric_name = slow_sql.metric_name
        @path = path
        @url = uri
        # FIXME
        @params[:backtrace] = slow_sql.backtrace if slow_sql.backtrace
      end

      def aggregate(slow_sql, path, uri)
        if slow_sql.duration > max_call_time
          set_primary slow_sql, path, uri
        end

        record_data_point slow_sql.duration
      end

      def prepare_to_send
        params[:explain_plan] = @slow_sql.explain if need_to_explain?
        @sql = @slow_sql.obfuscate if need_to_obfuscate?
      end

      def need_to_obfuscate?
        Agent.config[:'slow_sql.record_sql'].to_s == 'obfuscated'
      end

      def need_to_explain?
        Agent.config[:'slow_sql.explain_enabled']
      end

      def to_collector_array(encoder)
        [ @path, @url, @sql_id, @sql, @database_metric_name, @call_count,
          Helper.time_to_millis(@total_call_time),
          Helper.time_to_millis(@min_call_time),
          Helper.time_to_millis(@max_call_time),
          encoder.encode(@params) ]
      end

      private

      def consistent_hash(string)
        # need to hash the same way in every process
        Digest::MD5.hexdigest(string).hex \
          .modulo(2**31-1)  # ensure sql_id fits in an INT(11)
      end
    end
  end
end
