# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/transaction'

module NewRelic
  module Agent
    module Messaging
      extend self

      def start_amqp_publish_segment(library: nil,
                                     destination_name: nil,
                                     headers: nil,
                                     routing_key: nil,
                                     reply_to: nil,
                                     correlation_id: nil,
                                     exchange_type: nil)

        # ruby 2.0.0 does not support required kwargs
        raise ArgumentError, 'missing required argument: library' if library.nil?
        raise ArgumentError, 'missing required argument: destination_name' if destination_name.nil?
        raise ArgumentError, 'missing required argument: headers' if headers.nil?

        original_headers = headers.nil? ? nil : headers.dup

        segment = NewRelic::Agent::Transaction.start_message_broker_segment(
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

        segment
      end

      ROUTING_KEY_DESTINATION = NewRelic::Agent::AttributeFilter::DST_TRANSACTION_EVENTS |
                                NewRelic::Agent::AttributeFilter::DST_TRANSACTION_TRACER |
                                NewRelic::Agent::AttributeFilter::DST_ERROR_COLLECTOR

      def start_amqp_consume_segment(library: nil,
                                     destination_name: nil,
                                     delivery_info: nil,
                                     message_properties: nil,
                                     exchange_type: nil,
                                     queue_name: nil,
                                     subscribed: false)

        # ruby 2.0.0 does not support required kwargs
        raise ArgumentError, 'missing required argument: library' if library.nil?
        raise ArgumentError, 'missing required argument: destination_name' if destination_name.nil?
        raise ArgumentError, 'missing required argument: delivery_info' if delivery_info.nil?
        raise ArgumentError, 'missing required argument: message_properties' if message_properties.nil?

        segment = NewRelic::Agent::Transaction.start_message_broker_segment(
          action: :consume,
          library: library,
          destination_name: destination_name,
          destination_type: :exchange,
          message_properties: message_properties[:headers]
        )

        segment.params[:headers] = message_properties[:headers] if message_properties[:headers]
        segment.params[:routing_key] = delivery_info[:routing_key] if delivery_info[:routing_key]
        segment.params[:reply_to] = message_properties[:reply_to] if message_properties[:reply_to]
        segment.params[:queue_name] = queue_name if queue_name
        segment.params[:exchange_type] = exchange_type if exchange_type
        segment.params[:exchange_name] = delivery_info[:exchange_name] if delivery_info[:exchange_name]
        segment.params[:correlation_id] = message_properties[:correlation_id] if message_properties[:correlation_id]

        if segment.transaction && subscribed && delivery_info[:routing_key]
          segment.transaction.add_agent_attribute :"message.routingKey", delivery_info[:routing_key], ROUTING_KEY_DESTINATION
        end

        segment
      end
    end
  end
end
