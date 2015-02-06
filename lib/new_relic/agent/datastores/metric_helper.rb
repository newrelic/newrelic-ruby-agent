# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Datastores
      module MetricHelper
        def self.statement_metric_for(product, collection, operation)
          "Datastore/statement/#{product}/#{collection}/#{operation}"
        end

        def self.operation_metric_for(product, operation)
          "Datastore/operation/#{product}/#{operation}"
        end

        def self.context_metric
          if NewRelic::Agent::Transaction.recording_web_transaction?
            "Datastore/allWeb"
          else
            "Datastore/allOther"
          end
        end

        def self.metrics_for(product, collection, operation)
          [
            "Datastore/all",
            context_metric,
            statement_metric_for(product, collection, operation),
            operation_metric_for(product, operation)
          ]
        end
      end
    end
  end
end
