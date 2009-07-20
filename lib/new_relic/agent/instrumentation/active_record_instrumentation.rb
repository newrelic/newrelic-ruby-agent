
# NewRelic instrumentation for ActiveRecord
if defined?(ActiveRecord::Base) && !NewRelic::Control.instance['skip_ar_instrumentation']
  
  module NewRelic::Agent::Instrumentation::ActiveRecordInstrumentation

    def self.included(instrumented_class)
      instrumented_class.class_eval do
        alias_method :log_without_newrelic_instrumentation, :log
        alias_method :log, :log_with_newrelic_instrumentation
        protected :log
      end
    end
    
    def active_record_all_stats
      NewRelic::Agent.instance.stats_engine.get_stats_no_scope("ActiveRecord/all")
    end
    
    def log_with_newrelic_instrumentation(sql, name, &block)
      # Capture db config if we are going to try to get the explain plans
      if (defined?(ActiveRecord::ConnectionAdapters::MysqlAdapter) && self.is_a?(ActiveRecord::ConnectionAdapters::MysqlAdapter)) ||
       (defined?(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter) && self.is_a?(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter))
        supported_config = @config
      end
      if name && (parts = name.split " ") && parts.size == 2
        model = parts.first
        operation = parts.last.downcase
        metric_name = case operation
          when 'load' then 'find'
          when 'indexes', 'columns' then nil # fall back to DirectSQL
          when 'destroy', 'find', 'save', 'create' then operation
          when 'update' then 'save'
        else
          if model == 'Join'
            operation
          end
        end
        metric = "ActiveRecord/#{model}/#{metric_name}" if metric_name
      end      
      if metric.nil? && sql =~ /^(select|update|insert|delete)/i
        # Could not determine the model/operation so let's find a better
        # metric.  If it doesn't match the regex, it's probably a show
        # command or some DDL which we'll ignore.
        metric = "Database/SQL/#{$1.downcase}"
      end
      
      if !metric
        log_without_newrelic_instrumentation(sql, name, &block)
      else
        self.class.trace_method_execution_with_scope metric, true, true do        
          t0 = Time.now.to_f
          result = log_without_newrelic_instrumentation(sql, name, &block)
          duration = Time.now.to_f - t0
          
          NewRelic::Agent.instance.transaction_sampler.notice_sql(sql, supported_config, duration)
          # Record in the overall summary metric
          active_record_all_stats.record_data_point(duration)
          # Record in the summary metric for this operation
          NewRelic::Agent.instance.stats_engine.get_stats_no_scope("ActiveRecord/#{metric_name}").record_data_point(duration) if metric_name
          result
        end
      end
    end
    
  end
  
  # instrumentation to catch logged SQL statements in sampled transactions
  ActiveRecord::ConnectionAdapters::AbstractAdapter.module_eval do
    include ::NewRelic::Agent::Instrumentation::ActiveRecordInstrumentation
  end

  # This instrumentation will add an extra scope to the transaction traces
  # which will show the code surrounding the query, inside the model find_by_sql
  # method.
  ActiveRecord::Base.class_eval do
    class << self
      add_method_tracer :find_by_sql, 'ActiveRecord/#{self.name}/find_by_sql', :metric => false
    end
  end
 
end