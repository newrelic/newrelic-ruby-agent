# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../../test_helper', __FILE__)

require 'new_relic/agent/transaction'

module NewRelic
  module Agent
    class Transaction
      class AMQPAPITest < Minitest::Test

        def setup
          NewRelic::Agent.drop_buffered_data
        end

        def teardown
          NewRelic::Agent.drop_buffered_data
        end

        def test_metrics_recorded_for_amqp_publish
          in_transaction "test_txn" do
            segment = NewRelic::Agent::Transaction.start_amqp_publish_segment(
              library: "RabbitMQ",
              destination_name: "Default",
              headers: {foo: "bar"}
            )
            segment.finish
          end

          assert_metrics_recorded [
            ["MessageBroker/RabbitMQ/Exchange/Produce/Named/Default", "test_txn"],
            "MessageBroker/RabbitMQ/Exchange/Produce/Named/Default"
          ]
        end

        def test_metrics_recorded_for_amqp_consume
          in_transaction "test_txn" do
            segment = NewRelic::Agent::Transaction.start_amqp_consume_segment(
              library: "RabbitMQ",
              destination_name: "Default",
              delivery_info: {routing_key: "foo", exchange_name: "bar"},
              message_properties: {headers: {}}
            )

            segment.finish
          end

          assert_metrics_recorded [
            ["MessageBroker/RabbitMQ/Exchange/Consume/Named/Default", "test_txn"],
            "MessageBroker/RabbitMQ/Exchange/Consume/Named/Default"
          ]
        end

        def test_segment_parameters_recorded_for_publish
          in_transaction "test_txn" do
            headers = {foo: "bar"}
            segment = NewRelic::Agent::Transaction.start_amqp_publish_segment(
              library: "RabbitMQ",
              destination_name: "Default",
              headers: headers,
              routing_key: "red",
              reply_to: "blue",
              correlation_id: "abc",
              exchange_type: "direct"
            )

            assert_equal "red", segment.params[:routing_key]
            assert_equal headers, segment.params[:headers]
            assert_equal "blue", segment.params[:reply_to]
            assert_equal "abc", segment.params[:correlation_id]
            assert_equal "direct", segment.params[:exchange_type]
          end
        end

        def test_segment_parameters_recorded_for_consume
          in_transaction "test_txn" do
            message_properties = {headers: {foo: "bar"}, reply_to: "blue", correlation_id: "abc"}
            delivery_info      = {routing_key: "red", exchange_name: "foobar"}

            segment = NewRelic::Agent::Transaction.start_amqp_consume_segment(
              library: "RabbitMQ",
              destination_name: "Default",
              delivery_info: delivery_info,
              message_properties: message_properties,
              queue_name: "yellow",
              exchange_type: "direct"
            )

            assert_equal("red", segment.params[:routing_key])
            assert_equal({foo: "bar"}, segment.params[:headers])
            assert_equal("blue", segment.params[:reply_to])
            assert_equal("abc", segment.params[:correlation_id])
            assert_equal("direct", segment.params[:exchange_type])
            assert_equal("yellow", segment.params[:queue_name])
          end
        end

        def test_agent_attributes_assigned_when_in_transaction_and_subscribed
          in_transaction "test_txn" do
            message_properties = {headers: {foo: "bar"}, reply_to: "blue", correlation_id: "abc"}
            delivery_info      = {routing_key: "red", exchange_name: "foobar"}

            NewRelic::Agent::Transaction.start_amqp_consume_segment(
              library: "RabbitMQ",
              destination_name: "Default",
              delivery_info: delivery_info,
              message_properties: message_properties,
              queue_name: "yellow",
              exchange_type: "direct",
              subscribed: true
            )
          end
          event = last_transaction_event
          assert Array === event, "expected Array, actual: #{event.class}"
          assert_equal 3, event.length, "expected Array of 3 elements, actual: #{event.length}"
          assert event.all? {|e| Hash === e}, "expected Array of 3 hashes, actual: [#{event.map(&:class).join(',')}]"
          assert event[2].key?(:'message.routingKey'), "expected 3rd hash to have key :'message.routingKey', actual: #{event[2].keys.join(',')}"
          assert_equal "red", event[2][:'message.routingKey']
        end

        def test_agent_attributes_not_assigned_when_in_transaction_but_not_subscribed
          in_transaction "test_txn" do
            message_properties = {headers: {foo: "bar"}, reply_to: "blue", correlation_id: "abc"}
            delivery_info      = {routing_key: "red", exchange_name: "foobar"}

            NewRelic::Agent::Transaction.start_amqp_consume_segment(
              library: "RabbitMQ",
              destination_name: "Default",
              delivery_info: delivery_info,
              message_properties: message_properties,
              queue_name: "yellow",
              exchange_type: "direct",
              subscribed: false
            )
          end

          event = last_transaction_event
          assert_equal nil, event[2][:"message.routingKey"]
        end

        def test_agent_attributes_not_assigned_when_subscribed_but_not_in_transaction
          message_properties = {headers: {foo: "bar"}, reply_to: "blue", correlation_id: "abc"}
          delivery_info      = {routing_key: "red", exchange_name: "foobar"}

          segment = NewRelic::Agent::Transaction.start_amqp_consume_segment(
            library: "RabbitMQ",
            destination_name: "Default",
            delivery_info: delivery_info,
            message_properties: message_properties,
            queue_name: "yellow",
            exchange_type: "direct",
            subscribed: true
          )

          refute segment.transaction, "expected nil segment.transaction, actual: #{segment.transaction.inspect}"
          event = last_transaction_event
          refute event, "expected nil last_transaction_event, actual: #{event.inspect}"
        end

        def test_agent_attributes_not_assigned_when_not_subscribed_nor_in_transaction
          message_properties = {headers: {foo: "bar"}, reply_to: "blue", correlation_id: "abc"}
          delivery_info      = {routing_key: "red", exchange_name: "foobar"}

          segment = NewRelic::Agent::Transaction.start_amqp_consume_segment(
            library: "RabbitMQ",
            destination_name: "Default",
            delivery_info: delivery_info,
            message_properties: message_properties,
            queue_name: "yellow",
            exchange_type: "direct",
            subscribed: false
          )

          refute segment.transaction, "expected nil segment.transaction, actual: #{segment.transaction}"
          refute last_transaction_event, "expected nil last_transaction_event, actual: #{last_transaction_event}"
        end

        def test_consume_api_passes_message_properties_headers_to_underlying_api
          message_properties = {headers: {foo: "bar"}, reply_to: "blue", correlation_id: "abc"}
          delivery_info      = {routing_key: "red", exchange_name: "foobar"}

          segment = NewRelic::Agent::Transaction.start_amqp_consume_segment(
            library: "RabbitMQ",
            destination_name: "Default",
            delivery_info: delivery_info,
            message_properties: message_properties,
            queue_name: "yellow",
            exchange_type: "direct",
            subscribed: false
          )

          assert NewRelic::Agent::Transaction::MessageBrokerSegment === segment
          assert_equal message_properties[:headers], segment.message_properties
        end
      end
    end
  end
end
