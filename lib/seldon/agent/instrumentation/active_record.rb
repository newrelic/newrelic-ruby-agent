
# Seldon instrumentation for ActiveRecord
if defined? ActiveRecord

module ActiveRecord
  class Base
    class << self
      add_method_tracer :find, 'ActiveRecord/#{self.name}/find'
      add_method_tracer :find, 'ActiveRecord/find', false
      add_method_tracer :find, 'ActiveRecord/all', false
    end
    
    [:save, :save!].each do |save_method|
      add_method_tracer save_method, 'ActiveRecord/#{self.class.name}/save'
      add_method_tracer save_method, 'ActiveRecord/save', false
      add_method_tracer save_method, 'ActiveRecord/all', false
    end

    add_method_tracer :destroy, 'ActiveRecord/#{self.class.name}/destroy'
    add_method_tracer :destroy, 'ActiveRecord/destroy', false
    add_method_tracer :destroy, 'ActiveRecord/all', false
  end
  
  # instrumentation to catch logged SQL statements in sampled transactions
  module ConnectionAdapters
    class AbstractAdapter
      
      def log_with_capture_sql(sql, name, &block)
        Seldon::Agent.instance.transaction_sampler.notice_sql(sql)
        
        log_without_capture_sql(sql, name, &block)
      end
      alias_method_chain :log, :capture_sql
      
      # add_method_tracer :log, 'Database/#{self.adapter_name}/#{args[1] || "Custom SQL"}'
    end
  end
end

end