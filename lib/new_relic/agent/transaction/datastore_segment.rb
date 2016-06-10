# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/segment'
require 'new_relic/agent/datastores/metric_helper'

module NewRelic
  module Agent
    class Transaction
      class DatastoreSegment < Segment
        attr_reader :product, :operation, :collection

        def initialize product, operation, collection = nil
          @product = product
          @operation = operation
          @collection = collection

          super Datastores::MetricHelper.scoped_metric_for product, operation, collection
        end
      end
    end
  end
end
