# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Datastores
      module Mongo
        module Obfuscator

          WHITELIST = [:operation].freeze

          def self.obfuscate_statement(source, whitelist=WHITELIST)
            obfuscated = {}
            source.each do |key, value|
              if whitelist.include?(key)
                obfuscated[key] = value
              else
                obfuscated[key] = '?'
              end
            end

            obfuscated
          end
        end
      end
    end
  end
end
