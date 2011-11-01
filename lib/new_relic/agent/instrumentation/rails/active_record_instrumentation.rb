module NewRelic
  module Agent
    module Instrumentation
      module ActiveRecordInstrumentation

        def self.included(instrumented_class)
          instrumented_class.class_eval do
            alias_method :log_without_newrelic_instrumentation, :log
            alias_method :log, :log_with_newrelic_instrumentation
            protected :log
          end          
        end
        
        def log_with_newrelic_instrumentation(sql, name, &block)
          return log_without_newrelic_instrumentation(sql, name, &block) unless NewRelic::Agent.is_execution_traced?
          
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

          if metric.nil?
            metric = NewRelic::Agent::Instrumentation::MetricFrame.database_metric_name
            if metric.nil?
              if sql =~ /^(select|update|insert|delete|show)/i
                # Could not determine the model/operation so let's find a better
                # metric.  If it doesn't match the regex, it's probably a show
                # command or some DDL which we'll ignore.
                metric = "Database/SQL/#{$1.downcase}"
              else
                metric = "Database/SQL/other"
              end
            end
          end

          if !metric
            log_without_newrelic_instrumentation(sql, name, &block)
          else
            metrics = [metric, "ActiveRecord/all"]
            metrics << "ActiveRecord/#{metric_name}" if metric_name
            if NewRelic::Agent::Database.config && NewRelic::Agent::Database.config[:adapter]
              type = NewRelic::Agent::Database.config[:adapter].sub(/\d*/, '')
              host = NewRelic::Agent::Database.config[:host] || 'localhost'
              metrics << "RemoteService/sql/#{type}/#{host}"
            end
            
            self.class.trace_execution_scoped(metrics) do
              t0 = Time.now
              begin
                log_without_newrelic_instrumentation(sql, name, &block)
              ensure
                elapsed_time = (Time.now - t0).to_f
                NewRelic::Agent.instance.transaction_sampler.notice_sql(sql, NewRelic::Agent::Database.config,
                                                                        elapsed_time)
                NewRelic::Agent.instance.sql_sampler.notice_sql(sql, metric, NewRelic::Agent::Database.config,
                                                                elapsed_time)
              end
            end
          end
        end

      end
    end
  end
end

DependencyDetection.defer do
  @name = :rails2_active_record
  
  depends_on do
    defined?(ActiveRecord) && defined?(ActiveRecord::Base)
  end

  depends_on do
    defined?(::Rails) && ::Rails::VERSION::MAJOR.to_i == 2
  end

  depends_on do
    !NewRelic::Control.instance['skip_ar_instrumentation']
  end

  depends_on do
    !NewRelic::Control.instance['disable_activerecord_instrumentation']
  end
  
  executes do
    NewRelic::Agent.logger.debug 'Installing Rails 2 ActiveRecord instrumentation'
  end
  
  executes do
    ActiveRecord::ConnectionAdapters::AbstractAdapter.module_eval do
      include ::NewRelic::Agent::Instrumentation::ActiveRecordInstrumentation
    end
  end

  executes do
    ActiveRecord::Base.class_eval do
      NewRelic::Agent::Database::ConnectionManager.instance.config = connection.instance_eval{ @config }
      class << self
        add_method_tracer :find_by_sql, 'ActiveRecord/#{self.name}/find_by_sql', :metric => false
        add_method_tracer :transaction, 'ActiveRecord/#{self.name}/transaction', :metric => false
      end
    end
  end
end

DependencyDetection.detect!
