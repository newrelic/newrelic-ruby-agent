# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/segment'
require 'new_relic/agent/transaction/datastore_segment'
require 'new_relic/agent/transaction/external_request_segment'

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

          UNKNOWN_PRODUCT = "Unknown".freeze
          UNKNOWN_OPERATION = "other".freeze

          def start_datastore_segment product=nil, operation=nil, collection=nil, host=nil, port_path_or_id=nil, database_name=nil
            product ||= UNKNOWN_PRODUCT
            operation ||= UNKNOWN_OPERATION
            segment = DatastoreSegment.new product, operation, collection, host, port_path_or_id, database_name
            segment.start
            add_segment segment
            segment
          end

          def start_external_request_segment library, uri, procedure
            segment = ExternalRequestSegment.new library, uri, procedure
            segment.start
            add_segment segment
            segment
          end

          private

          def add_segment segment
            state = NewRelic::Agent::TransactionState.tl_get
            if (txn = state.current_transaction) && state.is_execution_traced?
              txn.add_segment segment
            else
              segment.record_metrics = false
            end
          end
        end

        def self.included base
          base.extend ClassMethods
        end

        attr_reader :current_segment

        def add_segment segment
          segment.transaction = self
          segment.parent = current_segment
          @current_segment = segment
          transaction_sampler.notice_push_frame state, segment.start_time if transaction_sampler_enabled?
        end

        def segment_complete segment
          @current_segment = segment.parent
          transaction_sampler.notice_pop_frame state, segment.name, segment.end_time if transaction_sampler_enabled?
        end

        private

        def transaction_sampler_enabled?
          Agent.config[:'transaction_tracer.enabled']
        end
      end
    end
  end
end
