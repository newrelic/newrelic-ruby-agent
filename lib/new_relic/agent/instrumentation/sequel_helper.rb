# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

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

        # Fallback if the product cannot be determined
        DEFAULT_PRODUCT_NAME = "ActiveRecord".freeze

        # A Sequel adapter is called an "adapter_scheme" and can be accessed from
        # the database:
        #
        #   DB.adapter_scheme
        PRODUCT_NAMES = {
          :mysql => "MySQL",
          :mysql2 => "MySQL",
          :postgres => "Postgres",
          :sqlite => "SQLite"
        }.freeze

        def product_name_from_adapter(adapter)
          PRODUCT_NAMES.fetch(adapter, DEFAULT_PRODUCT_NAME)
        end
      end
    end
  end
end