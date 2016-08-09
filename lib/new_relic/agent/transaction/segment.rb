# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/abstract_segment'

module NewRelic
  module Agent
    class Transaction
      class Segment < AbstractSegment
        # unscoped_metrics can be nil, a string, or array. we do this to save
        # object allocations. if allocations weren't important then we would
        # initialize it as an array that would be empty, have one item, or many items.
        attr_reader :unscoped_metrics

        def initialize name, unscoped_metrics=nil
          @unscoped_metrics = unscoped_metrics
          super name
        end

        def record_metrics
          metric_cache.record_scoped_and_unscoped name, duration, exclusive_duration
          if unscoped_metrics
            metric_cache.record_unscoped unscoped_metrics, duration, exclusive_duration
          end
        end
      end
    end
  end
end
