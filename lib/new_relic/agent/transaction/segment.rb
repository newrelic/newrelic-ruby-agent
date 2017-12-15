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

        def initialize name=nil, unscoped_metrics=nil, start_time=nil
          @unscoped_metrics = unscoped_metrics
          super name, start_time
        end

        private

        def record_metrics
          if record_scoped_metric?
            metric_cache.record_scoped_and_unscoped name, duration, exclusive_duration
          else
            append_unscoped_metric name
          end
          if unscoped_metrics
            metric_cache.record_unscoped unscoped_metrics, duration, exclusive_duration
          end
        end

        def append_unscoped_metric metric
          if @unscoped_metrics
            if Array === @unscoped_metrics
              if unscoped_metrics.frozen?
                @unscoped_metrics += [name]
              else
                @unscoped_metrics << name
              end
            else
              @unscoped_metrics = [@unscoped_metrics, metric]
            end
          else
            @unscoped_metrics = metric
          end
        end
      end
    end
  end
end
