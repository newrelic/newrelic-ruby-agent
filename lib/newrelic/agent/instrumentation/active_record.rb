
# NewRelic instrumentation for ActiveRecord
if defined? ActiveRecord

module ActiveRecord
  class Base
    class << self
      [:find, :count].each do |find_method|
        add_method_tracer find_method, 'ActiveRecord/#{self.name}/find'
        add_method_tracer find_method, 'ActiveRecord/find', false
        add_method_tracer find_method, 'ActiveRecord/all', false
      end
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
        NewRelic::Agent.instance.transaction_sampler.notice_sql(sql)
        
        log_without_capture_sql(sql, name, &block)
      end
      alias_method_chain :log, :capture_sql
      
      add_method_tracer :log, 'Database/#{adapter_name}/#{args[1]}' if ::RPM_DEVELOPER
    end
  end
  
  # instrumentation for associations
  module Associations
    class AssociationCollection
      add_method_tracer :delete, 'ActiveRecord/#{@owner.class.name}/association delete'
    end
    
    def HasAndBelongsToManyAssociation
      add_method_tracer :find, 'ActiveRecord/#{@owner.class.name}/association find'
      add_method_tracer :create_record, 'ActiveRecord/#{@owner.class.name}/association create'
      add_method_tracer :insert_record, 'ActiveRecord/#{@owner.class.name}/association insert'
    end
    
    class HasManyAssociation
      # add_method_tracer :find, 'ActiveRecord/#{@owner.class.name}/association find'
      # add_method_tracer :insert_record, 'ActiveRecord/#{@owner.class.name}/association insert'
      # add_method_tracer :create_record, 'ActiveRecord/#{@owner.class.name}/association create'
    end
  end
  
end

end