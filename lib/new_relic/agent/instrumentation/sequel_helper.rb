# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Instrumentation
      module SequelHelper
        extend self

        # Fallback if the product cannot be determined
        DEFAULT_PRODUCT_NAME = "Sequel".freeze

        # A Sequel adapter is called an "adapter_scheme" and can be accessed from
        # the database:
        #
        #   DB.adapter_scheme
        PRODUCT_NAMES = {
          :ibmdb => "IBMDB2",
          :firebird => "Firebird",
          :informix => "Informix",
          :jdbc => "JDBC",
          :mysql => "MySQL",
          :mysql2 => "MySQL",
          :oracle => "Oracle",
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
