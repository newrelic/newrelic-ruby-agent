# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/datastores/mongo/metric_translator'

module NewRelic
  module Agent
    module Datastores
      module Mongo
        module MetricGenerator
          def self.generate_metrics_for(name, payload)
            if NewRelic::Agent::Transaction.recording_web_transaction?
              request_type = :web
            else
              request_type = :other
            end

            NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(name, payload, request_type)
          rescue => e
            NewRelic::Agent.logger.debug("Failure during Mongo metric generation", e)
            []
          end

          def self.generate_instance_metric_for(host, port, database_name)
            return unless host && port && database_name
            NewRelic::Agent::Datastores::Mongo::MetricTranslator.instance_metric(host, port, database_name)
          end
        end
      end
    end
  end
end
