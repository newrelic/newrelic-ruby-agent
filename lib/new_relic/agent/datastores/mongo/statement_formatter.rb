# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/database'
require 'new_relic/agent/datastores/mongo/obfuscator'

module NewRelic
  module Agent
    module Datastores
      module Mongo
        module StatementFormatter
          def self.format(statement)
            statement = statement.dup
            modify_for_documents(statement)
            modify_for_selector(statement)
            statement
          end

          def self.modify_for_documents(statement)
            statement.delete(:documents)
          end

          def self.modify_for_selector(statement)
            case NewRelic::Agent::Database.record_sql_method
            when :obfuscated
              Obfuscator.obfuscate_statement(statement)
            when :off
              statement.delete(:selector)
            end
          end
        end
      end
    end
  end
end
