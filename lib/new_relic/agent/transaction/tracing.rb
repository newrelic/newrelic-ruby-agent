# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/segment'
require 'new_relic/agent/transaction/datastore_segment'

module NewRelic
  module Agent
    class Transaction
      module Tracing
        module ClassMethods
          def start_segment name, unscoped_metrics=nil
            segment = create_segment name, unscoped_metrics
            segment.start
            segment
          end

          def create_segment name, unscoped_metrics=nil
            segment = Segment.new name, unscoped_metrics
            if txn = tl_current
              txn.add_segment segment
            end
            segment
          end

          def start_datastore_segment product, operation, collection=nil
            segment = create_datastore_segment product, operation, collection
            segment.start
            segment
          end

          def create_datastore_segment product, operation, collection=nil
            segment = DatastoreSegment.new product, operation, collection
            if txn = tl_current
              txn.add_segment segment
            end
            segment
          end
        end

        def self.included base
          base.extend ClassMethods
        end

        def add_segment segment
          if state.is_execution_traced?
            segment.transaction = self
            state.traced_method_stack.push_segment state, segment
          else
            segment.ignore!
          end
        end

        def segment_complete segment
          state.traced_method_stack.pop_frame(state, segment, segment.name, segment.end_time, segment.record_metrics?)
        end
      end
    end
  end
end
