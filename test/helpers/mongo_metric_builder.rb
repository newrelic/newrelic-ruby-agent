# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/datastores/mongo/mongo_metric_translator'

module NewRelic
  module TestHelpers
    module MongoMetricBuilder
      def build_test_metrics(name, web = true)
        NewRelic::Agent::Datastores::Mongo::MetricTranslator.build_metrics(
          :name => name,
          :collection => @collection_name,
          :web => web
        )
      end

      def metrics_with_attributes(metrics, attributes)
        metric_attributes = {}

        metrics.each do |metric|
          metric_attributes[metric] = attributes
        end

        metric_attributes
      end
    end
  end
end
