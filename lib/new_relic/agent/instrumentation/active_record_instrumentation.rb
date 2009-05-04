
# NewRelic instrumentation for ActiveRecord
if defined?(ActiveRecord::Base) && !NewRelic::Control.instance['skip_ar_instrumentation']
  
  # instrumentation to catch logged SQL statements in sampled transactions
  
  ActiveRecord::ConnectionAdapters::AbstractAdapter.class_eval do
    
    def newrelic_ar_all_stats
      # need to lazy init this
      @@newrelic_ar_all ||= NewRelic::Agent.instance.stats_engine.get_stats_no_scope("ActiveRecord/all")
    end
    
    def log_with_newrelic_instrumentation(sql, name, &block)
      if (defined? ActiveRecord::ConnectionAdapters::MysqlAdapter && self.is_a?(ActiveRecord::ConnectionAdapters::MysqlAdapter)) ||
       (defined? ActiveRecord::ConnectionAdapters::PostgreSQLAdapter && self.is_a?(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter))
        supported_config = @config
      end
      
      if name.blank?
        metric = "Database/DirectSQL"
        operation = ""
      else
        a = name.split(" ")
        
        model = a[0]
        operation = a[1].downcase
        
        # we may want to leave the metric as "load" and adjust our UI.
        operation = "find" if operation == "load"
        
        metric = "ActiveRecord/#{model}/#{operation}"
      end
      
      result = nil
      
      self.class.trace_method_execution_with_scope metric, true, true do        
        t0 = Time.now.to_f
        
        result = log_without_newrelic_instrumentation(sql, name, &block)
        
        duration = Time.now.to_f - t0
        
        NewRelic::Agent.instance.transaction_sampler.notice_sql(sql, supported_config, duration)
        newrelic_ar_all_stats.record_data_point(duration)
        
        NewRelic::Agent.instance.stats_engine.get_stats_no_scope("ActiveRecord/#{operation}").record_data_point(duration)
      end
      
      result
    end
    
    alias_method :log_without_newrelic_instrumentation, :log
    alias_method :log, :log_with_newrelic_instrumentation
    protected :log
    
  end
  
end