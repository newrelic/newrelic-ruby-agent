
# NewRelic instrumentation for ActiveRecord
# This version of AR instrumentation only catches model access that
# ends up going to the database. Cached access is not traced
#
if false && defined? ActiveRecord
  
  # instrumentation to catch logged SQL statements in sampled transactions

  ActiveRecord::ConnectionAdapters::AbstractAdapter.class_eval do
    @@my_sql_defined = defined? ActiveRecord::ConnectionAdapters::MysqlAdapter
    @@postgres_defined = defined? ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
    
    @@ar_all = NewRelic::Agent.instance.stats_engine.get_stats_no_scope("ActiveRecord/all")
    
    
    def log_with_newrelic_instrumentation(sql, name, &block)
      if @@my_sql_defined && self.is_a?(ActiveRecord::ConnectionAdapters::MysqlAdapter)
        config = @config
      elsif @@postgres_defined && self.is_a?(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)
        config = @config
      else
        config = nil
      end
      
      operation = ""
      
      if name.blank?
        metric = "Database/DirectSQL"
      else
        a = name.split(" ")
        
        operation = a[1].downcase
          
        model = a[0]
          
        metric = "ActiveRecord/#{model}/#{operation}"
      end
      
      #puts "sql: #{metric}"
      
      result = nil
      
      self.class.trace_method_execution_with_scope metric, true, true do
        
        t0 = Time.now.to_f
      
        result = log_without_newrelic_instrumentation(sql, name, &block)
        
        duration = Time.now.to_f - t0
        
        NewRelic::Agent.instance.transaction_sampler.notice_sql(sql, config, duration)
        @@ar_all.record_data_point(duration)
        
        NewRelic::Agent.instance.stats_engine.get_stats_no_scope("ActiveRecord/#{operation}").record_data_point(duration)
      end
      
      result
    end

    alias_method :log_without_newrelic_instrumentation, :log
    alias_method :log, :log_with_newrelic_instrumentation
    protected :log
  end

end
