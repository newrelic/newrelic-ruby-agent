# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/datastores/mongo/metric_translator'

module NewRelic
  module TestHelpers
    module MongoMetricBuilder
      def build_test_metrics(name, instance_metrics=false)
        host = nil
        port = nil

        if instance_metrics
          host = NewRelic::Agent::Hostname.get
          port = 27017
        end

        NewRelic::Agent::Datastores::MetricHelper.metrics_for(
          "MongoDB", name, @collection_name, host, port)
      end

      def metrics_with_attributes(metrics, attributes = { :call_count => 1 })
        metric_attributes = {}

        metrics.each do |metric|
          metric_attributes[metric] = attributes.dup
        end

        metric_attributes
      end
    end
  end
end
