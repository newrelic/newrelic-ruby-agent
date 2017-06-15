# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/segment'
require 'new_relic/agent/transaction/datastore_segment'
require 'new_relic/agent/transaction/external_request_segment'
require 'new_relic/agent/transaction/message_broker_segment'

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

          def start_message_broker_segment(action:,
                                           library:,
                                           destination_type:,
                                           destination_name:,
                                           message_properties: nil,
                                           parameters: nil)

            segment = MessageBrokerSegment.new(
              action: action,
              library: library,
              destination_type: destination_type,
              destination_name: destination_name,
              message_properties: message_properties,
              parameters: parameters
            )
            segment.start
            add_segment segment
            segment
          rescue => e
            NewRelic::Agent.logger.error "Exception starting message broker segment", e
          end

          def start_amqp_publish_segment(library:,
                                         destination_name:,
                                         headers:,
                                         routing_key: nil,
                                         reply_to: nil,
                                         correlation_id: nil,
                                         exchange_type: nil)

            original_headers = headers.dup

            segment = start_message_broker_segment(
              action: :produce,
              library: library,
              destination_type: :exchange,
              destination_name: destination_name,
              message_properties: headers
            )

            segment.params[:headers] = original_headers if original_headers
            segment.params[:routing_key] = routing_key if routing_key
            segment.params[:reply_to] = reply_to if reply_to
            segment.params[:correlation_id] = correlation_id if correlation_id
            segment.params[:exchange_type] = exchange_type if exchange_type

            segment.start
            add_segment segment
            segment
          rescue => e
            NewRelic::Agent.logger.error "Exception starting AMQP segment", e
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
          if @segments.length < Agent.config[:'transaction_tracer.limit_segments']
            @segments << segment
            transaction_sampler.notice_push_frame state, segment.start_time if transaction_sampler_enabled?
          else
            segment.record_on_finish = true
          end
        end

        def segment_complete segment
          @current_segment = segment.parent
          if transaction_sampler_enabled? && !segment.record_on_finish?
            transaction_sampler.notice_pop_frame state, segment.name, segment.end_time
          end
        end

        private

        def transaction_sampler_enabled?
          Agent.config[:'transaction_tracer.enabled']
        end
      end
    end
  end
end
