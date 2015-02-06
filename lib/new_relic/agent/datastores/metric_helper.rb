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
      end
    end
  end
end
