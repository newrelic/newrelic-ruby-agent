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

      ATTR_DESTINATION = AttributeFilter::DST_TRANSACTION_EVENTS |
                         AttributeFilter::DST_TRANSACTION_TRACER |
                         AttributeFilter::DST_ERROR_COLLECTOR

      EMPTY_STRING = ''.freeze

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
      # @param headers [Hash] Metadata about the message and opaque
      #   application-level data (optional)
      #
      # @param parameters [Hash] A hash of parameters to be attached to this
      #   segment (optional)
      #
      # @param start_time [Time] An instance of Time class denoting the start
      #   time of the segment. Value is set by AbstractSegment#start if not
      #   given. (optional)
      #
      # @return [NewRelic::Agent::Transaction::MessageBrokerSegment]
      #
      # @api public
      #
      def start_message_broker_segment(action: nil,
                                       library: nil,
                                       destination_type: nil,
                                       destination_name: nil,
                                       headers: nil,
                                       parameters: nil,
                                       start_time: nil)

        Transaction.start_message_broker_segment(
          action: action,
          library: library,
          destination_type: destination_type,
          destination_name: destination_name,
          headers: headers,
          parameters: parameters,
          start_time: start_time
        )
      end

      # Wrap a MessageBroker transaction trace around a messaging handling block.
      # This API is intended to be used in library instrumentation when a "push"-
      # style callback is invoked to handle an incoming message.
      #
      # @param library [String] The name of the library being instrumented
      #
      # @param destination_type [Symbol] Type of destination (see
      #   +NewRelic::Agent::Transaction::MessageBrokerSegment::DESTINATION_TYPES+)
      #   for all options.
      #
      # @param destination_name [String] Name of destination (queue or
      #   exchange name)
      #
      # @param headers [Hash] Metadata about the message and opaque
      #   application-level data (optional)
      #
      # @param routing_key [String] Value used by AMQP message brokers to route
      #   messages to queues
      #
      # @param queue_name [String] Name of AMQP queue that received the
      #   message (optional)
      #
      # @param exchange_type [Symbol] Type of last AMQP exchange to deliver the
      #   message (optional)
      #
      # @param reply_to [String] Routing key to be used to send AMQP-based RPC
      #   response messages (optional)
      #
      # @param correlation_id [String] Application-level value used to correlate
      #   AMQP-based RPC response messages to request messages (optional)
      #
      # @param &block [Proc] The block should handle calling the original subscribed
      #   callback function
      #
      # @return return value of given block, which will be the same as the
      #   return value of an un-instrumented subscribed callback
      #
      # @api public
      #
      def wrap_message_broker_consume_transaction library: nil,
                                                  destination_type: nil,
                                                  destination_name: nil,
                                                  headers: nil,
                                                  routing_key: nil,
                                                  queue_name: nil,
                                                  exchange_type: nil,
                                                  reply_to: nil,
                                                  correlation_id: nil

        # ruby 2.0.0 does not support required kwargs
        raise ArgumentError, 'missing required argument: library' if library.nil?
        raise ArgumentError, 'missing required argument: destination_type' if destination_type.nil?
        raise ArgumentError, 'missing required argument: destination_name' if destination_name.nil?

        state = TransactionState.tl_get
        return yield if state.current_transaction
        txn = nil

        begin
          txn_name = transaction_name library, destination_type, destination_name
          txn = Transaction.start state, :message, transaction_name: txn_name

          if headers
            consume_message_headers headers, txn, state
            CrossAppTracing.reject_messaging_cat_headers(headers).each do |k, v|
              txn.add_agent_attribute :"message.headers.#{k}", v, AttributeFilter::DST_NONE unless v.nil?
            end
          end

          txn.add_agent_attribute :'message.routingKey', routing_key, ATTR_DESTINATION if routing_key
          txn.add_agent_attribute :'message.exchangeType', exchange_type, AttributeFilter::DST_NONE if exchange_type
          txn.add_agent_attribute :'message.correlationId', correlation_id, AttributeFilter::DST_NONE if correlation_id
          txn.add_agent_attribute :'message.queueName', queue_name, ATTR_DESTINATION if queue_name
          txn.add_agent_attribute :'message.replyTo', reply_to, AttributeFilter::DST_NONE if reply_to
        rescue => e
          NewRelic::Agent.logger.error "Error starting Message Broker consume transaction", e
        end

        yield
      ensure
        begin
          Transaction.stop(state) if txn
        rescue => e
          NewRelic::Agent.logger.error "Error stopping Message Broker consume transaction", e
        end
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
        raise ArgumentError, 'missing required argument: headers' if headers.nil? && CrossAppTracing.cross_app_enabled?

        original_headers = headers.nil? ? nil : headers.dup

        segment = Transaction.start_message_broker_segment(
          action: :produce,
          library: library,
          destination_type: :exchange,
          destination_name: destination_name,
          headers: headers
        )

        if segment_parameters_enabled?
          segment.params[:headers] = original_headers if original_headers && !original_headers.empty?
          segment.params[:routing_key] = routing_key if routing_key
          segment.params[:reply_to] = reply_to if reply_to
          segment.params[:correlation_id] = correlation_id if correlation_id
          segment.params[:exchange_type] = exchange_type if exchange_type
        end

        segment
      end

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
      # @param message_properties [Hash] AMQP-specific metadata about the message
      #   including headers and opaque application-level data
      #
      # @param exchange_type [String] Type of exchange which determines how
      #   messages are routed (optional)
      #
      # @param queue_name [String] The name of the queue the message was
      #   consumed from (optional)
      #
      # @param start_time [Time] An instance of Time class denoting the start
      #   time of the segment. Value is set by AbstractSegment#start if not
      #   given. (optional)
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
                                     start_time: nil)

        # ruby 2.0.0 does not support required kwargs
        raise ArgumentError, 'missing required argument: library' if library.nil?
        raise ArgumentError, 'missing required argument: destination_name' if destination_name.nil?
        raise ArgumentError, 'missing required argument: delivery_info' if delivery_info.nil?
        raise ArgumentError, 'missing required argument: message_properties' if message_properties.nil?

        segment = Transaction.start_message_broker_segment(
          action: :consume,
          library: library,
          destination_name: destination_name,
          destination_type: :exchange,
          headers: message_properties[:headers],
          start_time: start_time
        )

        if segment_parameters_enabled?
          if message_properties[:headers] && !message_properties[:headers].empty?
            non_cat_headers = CrossAppTracing.reject_messaging_cat_headers message_properties[:headers]
            non_synth_headers = SyntheticsMonitor.reject_messaging_synthetics_header non_cat_headers
            segment.params[:headers] = non_synth_headers unless non_synth_headers.empty?
          end

          segment.params[:routing_key] = delivery_info[:routing_key] if delivery_info[:routing_key]
          segment.params[:reply_to] = message_properties[:reply_to] if message_properties[:reply_to]
          segment.params[:queue_name] = queue_name if queue_name
          segment.params[:exchange_type] = exchange_type if exchange_type
          segment.params[:exchange_name] = delivery_info[:exchange_name] if delivery_info[:exchange_name]
          segment.params[:correlation_id] = message_properties[:correlation_id] if message_properties[:correlation_id]
        end

        segment
      end

      # Wrap a MessageBroker transaction trace around a AMQP messaging handling block.
      # This API is intended to be used in AMQP-specific library instrumentation when a
      # "push"-style callback is invoked to handle an incoming message.
      #
      # @param library [String] The name of the library being instrumented
      #
      # @param destination_name [String] Name of destination (queue or
      #   exchange name)
      #
      # @param message_properties [Hash] Metadata about the message and opaque
      #   application-level data (optional)
      #
      # @param exchange_type [Symbol] Type of AMQP exchange the message was recieved
      #   from (see NewRelic::Agent::Transaction::MessageBrokerSegment::DESTINATION_TYPES)
      #
      # @param queue_name [String] name of the AMQP queue on which the message was
      #   received
      #
      # @param &block [Proc] The block should handle calling the original subscribed
      #   callback function
      #
      # @return return value of given block, which will be the same as the
      #   return value of an un-instrumented subscribed callback
      #
      # @api public
      #
      def wrap_amqp_consume_transaction library: nil,
                                        destination_name: nil,
                                        delivery_info: nil,
                                        message_properties: nil,
                                        exchange_type: nil,
                                        queue_name: nil,
                                        &block

        wrap_message_broker_consume_transaction library: library,
                                                destination_type: :exchange,
                                                destination_name: Instrumentation::Bunny.exchange_name(destination_name),
                                                routing_key: delivery_info[:routing_key],
                                                reply_to: message_properties[:reply_to],
                                                queue_name: queue_name,
                                                exchange_type: exchange_type,
                                                headers: message_properties[:headers],
                                                correlation_id: message_properties[:correlation_id],
                                                &block
      end

      private

      def segment_parameters_enabled?
        NewRelic::Agent.config[:'message_tracer.segment_parameters.enabled']
      end

      def transaction_name library, destination_type, destination_name
        transaction_name = Transaction::MESSAGE_PREFIX + library
        transaction_name << Transaction::MessageBrokerSegment::SLASH
        transaction_name << Transaction::MessageBrokerSegment::TYPES[destination_type]
        transaction_name << Transaction::MessageBrokerSegment::SLASH

        case destination_type
        when :queue
          transaction_name << Transaction::MessageBrokerSegment::NAMED
          transaction_name << destination_name

        when :topic
          transaction_name << Transaction::MessageBrokerSegment::NAMED
          transaction_name << destination_name

        when :temporary_queue, :temporary_topic
          transaction_name << Transaction::MessageBrokerSegment::TEMP

        when :exchange
          transaction_name << Transaction::MessageBrokerSegment::NAMED
          transaction_name << destination_name

        end

        transaction_name
      end

      RABBITMQ_TRANSPORT_TYPE = "RabbitMQ".freeze

      def consume_message_headers headers, transaction, state
        consume_distributed_tracing_headers headers, transaction
        consume_cross_app_tracing_headers headers, state

        assign_synthetics_header headers[CrossAppTracing::NR_MESSAGE_BROKER_SYNTHETICS_HEADER], transaction
      rescue => e
        NewRelic::Agent.logger.error "Error in consume_message_headers", e
      end

      def decode_id encoded_id, transaction_state
        decoded_id = if encoded_id.nil?
                       EMPTY_STRING
                     else
                       CrossAppTracing.obfuscator.deobfuscate(encoded_id)
                     end
        if CrossAppTracing.trusted_valid_cross_app_id? decoded_id
          transaction_state.client_cross_app_id = decoded_id
        end
      end

      def decode_txn_info txn_header, transaction_state
        begin
          txn_info = ::JSON.load(CrossAppTracing.obfuscator.deobfuscate(txn_header))
          transaction_state.referring_transaction_info = txn_info
        rescue => e
          NewRelic::Agent.logger.debug("Failure deserializing encoded header in #{self.class}, #{e.class}, #{e.message}")
          nil
        end
      end

      CANDIDATE_HEADERS = ['newrelic'.freeze, 'NEWRELIC'.freeze, 'Newrelic'.freeze]

      def consume_distributed_tracing_headers headers, transaction
        if Agent.config[:'distributed_tracing.enabled']
          return unless newrelic_trace_key = CANDIDATE_HEADERS.detect do |key|
            headers.has_key?(key)
          end

          return unless payload = headers[newrelic_trace_key]

          if transaction.accept_distributed_trace_payload payload
            transaction.distributed_trace_payload.caller_transport_type = RABBITMQ_TRANSPORT_TYPE
          end
        end
      end

      def consume_cross_app_tracing_headers headers, state
        if CrossAppTracing.cross_app_enabled? && CrossAppTracing.message_has_crossapp_request_header?(headers)
          decode_id headers[CrossAppTracing::NR_MESSAGE_BROKER_ID_HEADER], state
          decode_txn_info headers[CrossAppTracing::NR_MESSAGE_BROKER_TXN_HEADER], state
          CrossAppTracing.assign_intrinsic_transaction_attributes state
        end
      end

      def assign_synthetics_header synthetics_header, transaction
        if synthetics_header and
           incoming_payload = ::JSON.load(CrossAppTracing.obfuscator.deobfuscate(synthetics_header)) and
           SyntheticsMonitor.is_valid_payload?(incoming_payload) and
           SyntheticsMonitor.is_supported_version?(incoming_payload) and
           SyntheticsMonitor.is_trusted?(incoming_payload)

          transaction.raw_synthetics_header = synthetics_header
          transaction.synthetics_payload = incoming_payload
        end
      rescue => e
        NewRelic::Agent.logger.error "Error in assign_synthetics_header", e
      end

    end
  end
end
