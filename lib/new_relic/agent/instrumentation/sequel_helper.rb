module NewRelic
  module Agent
    module Instrumentation
      module SequelHelper
        extend self

        OPERATIONS = {
          'all' => 'select',
          'first' => 'select',
          'get' => 'select',
          'update' => 'update',
          'update_all' => 'update',
          'update_except' => 'update',
          'update_fields' => 'update',
          'update_only' => 'update',
          'create' => 'insert',
          'save' => 'insert',
          'delete' => 'delete',
          'destroy' => 'delete'
        }

        def operation_from_method_name(method_name)
          OPERATIONS[method_name]
        end
      end
    end
  end
end