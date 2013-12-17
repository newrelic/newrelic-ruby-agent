# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Datastores
      module Mongo
        module MetricTranslator
          def self.metrics_for(name, payload, request_type = :web)
            payload = {} if payload.nil?

            collection = payload[:collection]

            if collection_in_selector?(collection, payload)
              name_key = name_key_from_selector(payload)
              if name_key
                name = name_key.to_sym
                collection = payload[:selector][name_key]
              end
            end

            if self.find_one?(name, payload)
              name = 'findOne'
            elsif self.find_and_remove?(name, payload)
              name = 'findAndRemove'
            elsif self.find_and_modify?(name, payload)
              name = 'findAndModify'
            elsif self.create_index?(name, payload)
              name = 'createIndex'
              collection = self.collection_name_from_index(payload)
            elsif self.drop_indexes?(name, payload)
              name = 'dropIndexes'
            elsif self.drop_index?(name, payload)
              name = 'dropIndex'
            elsif self.re_index?(name, payload)
              name = 'reIndex'
            elsif self.group?(name, payload)
              name = 'group'
              collection = collection_name_from_group_selector(payload)
            elsif self.rename_collection?(name, payload)
              name = 'renameCollection'
              collection = collection_name_from_rename_selector(payload)
            elsif self.ismaster?(name, payload)
              name = 'ismaster'
              collection = collection_name_from_ismaster_selector(payload)
            end

            build_metrics(name, collection, request_type)
          end

          def self.build_metrics(name, collection, request_type = :web)
            default_metrics = [
              "Datastore/statement/MongoDB/#{collection}/#{name}",
              "Datastore/operation/MongoDB/#{name}",
              'ActiveRecord/all'
            ]

            if request_type == :web
              default_metrics << 'Datastore/allWeb'
            else
              default_metrics << 'Datastore/allOther'
            end

            default_metrics
          end

          def self.collection_in_selector?(collection, payload)
            collection == '$cmd' && payload[:selector]
          end

          NAMES_IN_SELECTOR = [
            "count",
            "group",
            :distinct,
            :findandmodify,
            :deleteIndexes,
            :reIndex,
            :renameCollection,
            :ismaster
          ]

          def self.name_key_from_selector(payload)
            selector = payload[:selector]
            NAMES_IN_SELECTOR.find do |check_name|
              selector.key?(check_name)
            end
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

          def self.group?(name, payload)
            name == :group
          end

          def self.rename_collection?(name, payload)
            name == :renameCollection
          end

          def self.ismaster?(name, payload)
            name == :ismaster
          end

          def self.collection_name_from_index(payload)
            if payload[:documents] && payload[:documents].first[:ns]
              payload[:documents].first[:ns].split('.').last
            else
              'system.indexes'
            end
          end

          def self.collection_name_from_group_selector(payload)
            payload[:selector]["group"]["ns"]
          end

          def self.collection_name_from_rename_selector(payload)
            parts = payload[:selector][:renameCollection].split('.')
            parts.shift
            parts.join('.')
          end

          def self.collection_name_from_ismaster_selector(payload)
            payload[:selector][:ismaster]
          end

        end

      end
    end
  end
end
