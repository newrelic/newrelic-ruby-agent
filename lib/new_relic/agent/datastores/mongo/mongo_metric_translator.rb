# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Datastores
      module Mongo
        module MetricTranslator
          def self.metrics_for(name, payload)
            payload = {} if payload.nil?

            collection = payload[:collection]

            if collection == '$cmd' && payload[:selector]
              name_and_collection = payload[:selector].first
              name, collection = name_and_collection if name_and_collection
            end

            if self.find_one?(name, payload)
              name = 'find_one'
            elsif self.find_and_remove?(name, payload)
              name = 'find_and_remove'
            elsif self.find_and_modify?(name, payload)
              name = 'find_and_modify'
            elsif self.create_index?(name, payload)
              name = 'create_index'
              collection = self.collection_name_from_index(payload)
            elsif self.drop_indexes?(name, payload)
              name = 'drop_indexes'
            elsif self.drop_index?(name, payload)
              name = 'drop_index'
            elsif self.re_index?(name, payload)
              name = 're_index'
              collection = payload[:selector][:reIndex]
            end

            build_metrics(:name => name, :collection => collection)
          end

          def self.build_metrics(options)
            name, collection = options[:name], options[:collection]
            web_request = options.fetch(:web, true)

            default_metrics = [
              "Datastore/statement/MongoDB/#{collection}/#{name}",
              "Datastore/operation/MongoDB/#{name}",
              'ActiveRecord/all'
            ]

            if web_request
              default_metrics << 'Datastore/allWeb'
            else
              default_metrics << 'Datastore/allOther'
            end

            default_metrics
          end

          def self.find_one?(name, payload)
            name == :find && payload[:limit] == -1
          end

          def self.find_and_modify?(name, payload)
            name == :findandmodify
          end

          def self.find_and_remove?(name, payload)
            name == :findandmodify && payload[:selector] && payload[:selector][:remove]
          end

          def self.create_index?(name, payload)
            name == :insert && payload[:collection] == "system.indexes"
          end

          def self.drop_indexes?(name, payload)
            name == :deleteIndexes && payload[:selector] && payload[:selector][:index] == "*"
          end

          def self.drop_index?(name, payload)
            name == :deleteIndexes
          end

          def self.re_index?(name, payload)
            name == :reIndex && payload[:selector] && payload[:selector][:reIndex]
          end

          def self.collection_name_from_index(payload)
            if payload[:documents] && payload[:documents].first[:ns]
              payload[:documents].first[:ns].split('.').last
            else
              'system.indexes'
            end
          end

        end

      end
    end
  end
end
