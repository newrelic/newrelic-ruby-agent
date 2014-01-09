# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/datastores/mongo/metric_translator'

module NewRelic
  module Agent
    module Datastores
      module Mongo
        module MetricGenerator
          def self.generate_metrics_for(name, payload, host = nil, port = nil)
            if NewRelic::Agent::Transaction.recording_web_transaction?
              request_type = :web
            else
              request_type = :other
            end

            metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(name, payload, request_type)

            if host && port
              metrics << NewRelic::Agent::Datastores::Mongo::MetricTranslator.instance_metric(host, port)
            end

            metrics
          end
        end
      end
    end
  end
end
