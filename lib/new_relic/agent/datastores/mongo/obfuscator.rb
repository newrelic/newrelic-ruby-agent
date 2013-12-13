# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Datastores
      module Mongo
        module Obfuscator
          def self.obfuscate_statement(statement)
            statement = self.obfuscate_selector_values(statement)
          end

          def self.obfuscate_selector_values(statement)
            return statement unless selector = statement[:selector]

            new_selector = {}
            selector.each do |key, value|
              selector.delete(key)
              new_selector[key] = '?'
            end

            statement[:selector] = new_selector

            statement
          end
        end
      end
    end
  end
end
