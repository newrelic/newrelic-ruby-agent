# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Datastores
      module Mongo
        module Obfuscator

          WHITELIST = [:operation].freeze

          def self.obfuscate_statement(source, whitelist = WHITELIST)
            obfuscated = {}
            source.each do |key, value|
              if whitelist.include?(key)
                obfuscated[key] = value
              else
                obfuscated[key] = obfuscate_value(value, whitelist)
              end
            end

            obfuscated
          end

          def self.obfuscate_value(value, whitelist = WHITELIST)
            if value.is_a?(Hash)
              obfuscate_statement(value, whitelist)
            elsif value.is_a?(Array)
              value.map {|v| obfuscate_value(v, whitelist)}
            else
              '?'
            end
          end
        end
      end
    end
  end
end
