# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/abstract_segment'
require 'new_relic/agent/span_event_primitive'
require 'new_relic/agent/attributes'

module NewRelic
  module Agent
    class Transaction
      class Segment < AbstractSegment
        # unscoped_metrics can be nil, a string, or array. we do this to save
        # object allocations. if allocations weren't important then we would
        # initialize it as an array that would be empty, have one item, or many items.
        attr_reader :unscoped_metrics, :attributes

        def initialize name=nil, unscoped_metrics=nil, start_time=nil
          @unscoped_metrics = unscoped_metrics

          @attributes = Attributes.new(attribute_filter)
          super name, start_time
        end

        def add_custom_attributes(p)
          attributes.merge_custom_attributes(p)
        end

        private

        def attribute_filter
          # If no NewRelic::Agent instance has been started (for example, when
          # running a test suite), create an attribute filter using default
          # config settings. This avoids a NoMethodError caused by calling
          # .attribute_filter on nil and provides an inoffensive default
          # AttributeFilter.
          if NewRelic::Agent.instance
            NewRelic::Agent.instance.attribute_filter
          else
            AttributeFilter.new(NewRelic::Agent.config)
          end
        end

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

        def segment_complete
          record_span_event if transaction.sampled?
        end

        def record_span_event
          aggregator = ::NewRelic::Agent.agent.span_event_aggregator
          priority   = transaction.priority

          aggregator.record(priority: priority) do
            SpanEventPrimitive.for_segment(self)
          end
        end
      end
    end
  end
end
