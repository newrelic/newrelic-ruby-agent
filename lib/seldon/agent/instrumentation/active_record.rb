
# Seldon instrumentation for ActiveRecord
if defined? ActiveRecord

module ActiveRecord
  class Base
    class << self
      add_method_tracer :find, 'ActiveRecord/#{self.name}/find'
      add_method_tracer :find, 'ActiveRecord/find', false
      add_method_tracer :find, 'ActiveRecord/all', false
    end
    
    add_method_tracer :create_or_update, 'ActiveRecord/#{self.class.name}/save'
    add_method_tracer :create_or_update, 'ActiveRecord/save', false
    add_method_tracer :create_or_update, 'ActiveRecord/all', false

    add_method_tracer :destroy, 'ActiveRecord/#{self.class.name}/destroy'
    add_method_tracer :destroy, 'ActiveRecord/destroy', false
    add_method_tracer :destroy, 'ActiveRecord/all', false
  end
end

end