
# NewRelic instrumentation for DataMapper
# For now, we have to refer to all db metrics as "ActiveRecord"
if defined? DataMapper

  DataMapper::Model.class_eval do
    add_method_tracer :get, 'ActiveRecord/#{self.name}/find'
    add_method_tracer :first, 'ActiveRecord/#{self.name}/find'
    add_method_tracer :first_or_create, 'ActiveRecord/#{self.name}/find'
    add_method_tracer :all, 'ActiveRecord/#{self.name}/find_all'
  end
  DataMapper::Resource.class_eval do

    @@my_sql_defined = defined? ActiveRecord::ConnectionAdapters::MysqlAdapter
    @@postgres_defined = defined? ActiveRecord::ConnectionAdapters::PostgreSQLAdapter

    for method in [:query] do
      add_method_tracer method, 'ActiveRecord/#{self.class.name[/[^:]*$/]}/execute'
      add_method_tracer method, 'ActiveRecord/all', :push_scope => false
    end
    for method in [:update, :save] do
      add_method_tracer method, 'ActiveRecord/#{self.class.name[/[^:]*$/]}/save'
      add_method_tracer method, 'ActiveRecord/save', :push_scope => false
    end
    add_method_tracer :destroy, 'ActiveRecord/#{self.class.name[/[^:]*$/]}/destroy'
    add_method_tracer :destroy, 'ActiveRecord/destroy', :push_scope => false

    def log_with_newrelic_instrumentation(sql, name, &block)
      # if we aren't in a blamed context, then add one so that we can
      # see that controllers are calling SQL directly we check
      # scope_depth vs 2 since the controller is 1
      if NewRelic::Agent.instance.transaction_sampler.scope_depth < 2
        self.class.trace_method_execution "Database/DirectSQL", true, true do
          log_with_capture_sql(sql, name, &block)
        end
      else
        log_with_capture_sql(sql, name, &block)
      end
    end

    def log_with_capture_sql(sql, name, &block)
      if @@my_sql_defined && self.is_a?(ActiveRecord::ConnectionAdapters::MysqlAdapter)
        config = @config
      elsif @@postgres_defined && self.is_a?(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)
        config = @config
      else
        config = nil
      end

      t0 = Time.now
      result = log_without_newrelic_instrumentation(sql, name, &block)

      NewRelic::Agent.instance.transaction_sampler.notice_sql(sql, config, (Time.now - t0).to_f)

      result
    end
  end
end
