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
            segment = Segment.new name, unscoped_metrics
            segment.start
            add_segment segment
            segment
          end

          def start_datastore_segment product, operation, collection=nil
            segment = DatastoreSegment.new product, operation, collection
            segment.start
            add_segment segment
            segment
          end

          private

          def add_segment segment
            state = NewRelic::Agent::TransactionState.tl_get
            segment.record_metrics = state.is_execution_traced?
            if (txn = state.current_transaction) && state.is_execution_traced?
              txn.add_segment segment
            end
          end
        end

        def self.included base
          base.extend ClassMethods
        end

        def add_segment segment
          segment.transaction = self
          state.traced_method_stack.push_segment state, segment
        end

        def segment_complete segment
          state.traced_method_stack.pop_frame(state, segment, segment.name, segment.end_time, segment.record_metrics?)
        end
      end
    end
  end
end
