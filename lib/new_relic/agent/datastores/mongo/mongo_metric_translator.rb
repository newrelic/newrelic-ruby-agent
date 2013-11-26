# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    MONGO_METRICS = {
      :all => 'Datastore/all',
      :web => 'Datastore/allWeb',
      :other => 'Datastore/allOther',
      :operation => 'Datastore/operation/MongoDB/',
      :statement => 'Datastore/statement/MongoDB/',
      :insert => 'insert',
      :find => 'find',
      :find_one => 'find_one',
      :remove => 'remove',
      :save => 'save',
      :update => 'update',
      :distinct => 'distinct',
      :count => 'count',
      :find_and_modify => 'find_and_modify',
      :find_and_remove => 'find_and_remove',
      :create_index => 'create_index',
      :ensure_index => 'ensure_index',
      :drop_index => 'drop_index',
      :drop_indexes => 'drop_indexes',
      :re_index => 're_index'
    }

    module MongoMetricTranslator
      def self.metrics_for(name, payload = {})
        payload = {} if payload.nil?

        collection = payload[:collection]

        if collection == '$cmd'
          name_and_collection = payload[:selector].first
          name, collection = name_and_collection if name_and_collection
        end

        if self.find_one?(name, payload)
          name = NewRelic::Agent::MONGO_METRICS[:find_one]
        elsif self.find_and_remove?(name, payload)
          name = NewRelic::Agent::MONGO_METRICS[:find_and_remove]
        elsif self.find_and_modify?(name, payload)
          name = NewRelic::Agent::MONGO_METRICS[:find_and_modify]
        elsif self.create_index?(name, payload)
          name = NewRelic::Agent::MONGO_METRICS[:create_index]
          collection = self.collection_name_from_index(payload)
        elsif self.drop_indexes?(name, payload)
          name = NewRelic::Agent::MONGO_METRICS[:drop_indexes]
        elsif self.drop_index?(name, payload)
          name = NewRelic::Agent::MONGO_METRICS[:drop_index]
        elsif self.re_index?(name, payload)
          name = NewRelic::Agent::MONGO_METRICS[:re_index]
          collection = payload[:selector][:reIndex]
        end

        build_metrics(name, collection)
      end

      def self.build_metrics(name, collection)
        [
          "#{NewRelic::Agent::MONGO_METRICS[:statement]}#{collection}/#{name}",
          "#{NewRelic::Agent::MONGO_METRICS[:operation]}#{name}",
          NewRelic::Agent::MONGO_METRICS[:all]
        ]
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
