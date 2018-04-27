# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/datastores/mongo/obfuscator'

module NewRelic
  module Agent
    module Datastores
      module Mongo
        module EventFormatter

          # Keys that will get their values replaced with '?'.
          OBFUSCATE_KEYS = [ 'filter', 'query', 'pipeline' ].freeze

          # Keys that will get completely removed from the statement.
          BLACKLISTED_KEYS = [ 'deletes', 'documents', 'updates' ].freeze

          def self.format(command_name, database_name, command)
            return nil unless NewRelic::Agent.config[:'mongo.capture_queries']

            result = {
              :operation => command_name,
              :database => database_name,
              :collection => command.values.first
            }

            command.each do |key, value|
              next if BLACKLISTED_KEYS.include?(key)
              if OBFUSCATE_KEYS.include?(key)
                obfuscated = obfuscate(value)
                result[key] = obfuscated if obfuscated
              else
                result[key] = value
              end
            end
            result
          end

          def self.obfuscate(statement)
            if NewRelic::Agent.config[:'mongo.obfuscate_queries']
              statement = Obfuscator.obfuscate_statement(statement)
            end
            statement
          end
        end
      end
    end
  end
end
