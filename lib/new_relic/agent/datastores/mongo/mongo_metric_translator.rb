# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module MongoMetricTranslator
      def self.metrics_for(name, payload = {})
        payload = {} if payload.nil?

        collection = payload[:collection]

        if collection == '$cmd'
          f = payload[:selector].first
          name, collection = f if f
        end

        [
          "Datastore/all",
          "Datastore/operation/MongoDB/#{name}",
          "Datastore/statement/MongoDB/#{collection}/#{name}"
        ]
      end
    end
  end
end
