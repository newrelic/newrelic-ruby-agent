# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/transaction'

module NewRelic
  module Agent
    #
    # This module contains helper methods to facilitate instrumentation of
    # message brokers.
    #
    # @api public
    module Messaging
      extend self

      # Start a MessageBroker segment configured to trace a messaging action.
      # Finishing this segment will handle timing and recording of the proper
      # metrics for New Relic's messaging features..
      #
      # @param action [Symbol] The message broker action being traced (see
      #   NewRelic::Agent::Transaction::MessageBrokerSegment::ACTIONS) for
      #   all options.
      #
      # @param library [String] The name of the library being instrumented
      #
      # @param destination_type [Symbol] Type of destination (see
      #   NewRelic::Agent::Transaction::MessageBrokerSegment::DESTINATION_TYPES)
      #   for all options.
      #
      # @param destination_name [String] Name of destination (queue or
      #   exchange name)
      #
      # @param message_properties [Hash] Metadata about the message and opaque
      #   application-level data (optional)
      #
      # @param parameters [Hash] A hash of parameters to be attached to this
      #   segment (optional)
      #
      # @return [NewRelic::Agent::Transaction::MessageBrokerSegment]
      #
      # @api public
      #
      def start_message_broker_segment(action: nil,
                                       library: nil,
                                       destination_type: nil,
                                       destination_name: nil,
                                       message_properties: nil,
                                       parameters: nil)

        NewRelic::Agent::Transaction.start_message_broker_segment(
          action: action,
          library: library,
          destination_type: destination_type,
          destination_name: destination_name,
          message_properties: message_properties,
          parameters: parameters
        )
      end

      # Start a MessageBroker segment configured to trace an AMQP publish.
      # Finishing this segment will handle timing and recording of the proper
      # metrics for New Relic's messaging features. This method is a convenience
      # wrapper around NewRelic::Agent::Transaction.start_message_broker_segment.
      #
      # @param library [String] The name of the library being instrumented
      #
      # @param destination_name [String] Name of destination (exchange name)
      #
      # @param headers [Hash] The message headers
      #
      # @param routing_key [String] The routing key used for the message (optional)
      #
      # @param reply_to [String] A routing key for use in RPC-models for the
      #   receiver to publish a response to (optional)
      #
      # @param correlation_id [String] An application-generated value to link up
      #   request and responses in RPC-models (optional)
      #
      # @param exchange_type [String] Type of exchange which determines how
      #   message are routed (optional)
      #
      # @return [NewRelic::Agent::Transaction::MessageBrokerSegment]
      #
      # @api public
      #
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
        raise ArgumentError, 'missing required argument: headers' if headers.nil? && NewRelic::Agent::CrossAppTracing.cross_app_enabled?

        original_headers = headers.nil? ? nil : headers.dup

        segment = NewRelic::Agent::Transaction.start_message_broker_segment(
          action: :produce,
          library: library,
          destination_type: :exchange,
          destination_name: destination_name,
          message_properties: headers
        )

        segment.params[:headers] = original_headers if original_headers && !original_headers.empty?
        segment.params[:routing_key] = routing_key if routing_key
        segment.params[:reply_to] = reply_to if reply_to
        segment.params[:correlation_id] = correlation_id if correlation_id
        segment.params[:exchange_type] = exchange_type if exchange_type

        segment
      end

      ROUTING_KEY_DESTINATION = NewRelic::Agent::AttributeFilter::DST_TRANSACTION_EVENTS |
                                NewRelic::Agent::AttributeFilter::DST_TRANSACTION_TRACER |
                                NewRelic::Agent::AttributeFilter::DST_ERROR_COLLECTOR

      # Start a MessageBroker segment configured to trace an AMQP consume.
      # Finishing this segment will handle timing and recording of the proper
      # metrics for New Relic's messaging features. This method is a convenience
      # wrapper around NewRelic::Agent::Transaction.start_message_broker_segment.
      #
      # @param library [String] The name of the library being instrumented
      #
      # @param destination_name [String] Name of destination (exchange name)
      #
      # @param delivery_info [Hash] Metadata about how the message was delivered
      #
      # @param message_properties [Hash] Metadata about the message and opaque
      #   application-level data
      #
      # @param exchange_type [String] Type of exchange which determines how
      #   messages are routed (optional)
      #
      # @param queue_name [String] The name of the queue the message was
      #   consumed from (optional)
      #
      # @param subscribed [Boolean] Indicates that this trace is the result of
      #   subscription to queue (optional)
      #
      # @return [NewRelic::Agent::Transaction::MessageBrokerSegment]
      #
      # @api public
      #
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

        if message_properties[:headers] && !message_properties[:headers].empty?
          non_cat_headers = CrossAppTracing.reject_cat_headers message_properties[:headers]
          segment.params[:headers] = non_cat_headers unless non_cat_headers.empty?
        end
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
