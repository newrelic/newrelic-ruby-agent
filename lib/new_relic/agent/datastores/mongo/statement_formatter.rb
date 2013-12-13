# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/datastores/mongo/obfuscator'

module NewRelic
  module Agent
    module Datastores
      module Mongo
        module StatementFormatter
          def self.format(statement)
            statement.delete(:documents)
            NewRelic::Agent::Datastores::Mongo::Obfuscator.obfuscate_statement(statement)
          end
        end
      end
    end
  end
end
