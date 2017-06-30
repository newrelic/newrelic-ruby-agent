# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)

require 'new_relic/agent/messaging'
require 'new_relic/agent/transaction'

module NewRelic
  module Agent
    class MessagingTest < Minitest::Test

      def setup
        NewRelic::Agent.drop_buffered_data
      end

      def teardown
        NewRelic::Agent.drop_buffered_data
      end

      def test_metrics_recorded_for_amqp_publish
        in_transaction "test_txn" do
          segment = NewRelic::Agent::Messaging.start_amqp_publish_segment(
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
          segment = NewRelic::Agent::Messaging.start_amqp_consume_segment(
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
          segment = NewRelic::Agent::Messaging.start_amqp_publish_segment(
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

          segment = NewRelic::Agent::Messaging.start_amqp_consume_segment(
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

      def test_wrap_message_broker_consume_transaction
        tap = mock 'tap'
        tap.expects :tap

        NewRelic::Agent::Messaging.wrap_message_broker_consume_transaction(
          library: "AwesomeBunniez",
          destination_type: :exchange,
          destination_name: "Default",
          attributes: {:'message.routingKey' => 'red'}
        ) do
          assert_equal 'OtherTransaction/Message/AwesomeBunniez/Exchange/Named/Default', NewRelic::Agent.get_transaction_name
          tap.tap
        end

        txn = last_transaction_trace
        assert txn.finished, "Expected transaction to be finished"
      end

      def test_agent_attributes_assigned_for_generic_wrap_consume_transaction
        tap = mock 'tap'
        tap.expects :tap

        NewRelic::Agent::Messaging.wrap_message_broker_consume_transaction(
          library: "RabbitMQ",
          destination_type: :exchange,
          destination_name: "Default",
          attributes: {:'message.routingKey' => 'red'}
        ) { tap.tap }

        event = last_transaction_event
        assert Array === event, "expected Array, actual: #{event.class}"
        assert_equal 3, event.length, "expected Array of 3 elements, actual: #{event.length}"
        assert event.all? {|e| Hash === e}, "expected Array of 3 hashes, actual: [#{event.map(&:class).join(',')}]"
        assert event[2].key?(:'message.routingKey'), "expected 3rd hash to have key :'message.routingKey', actual: #{event[2].keys.join(',')}"
        assert_equal "red", event[2][:'message.routingKey']
      end

      def test_agent_attributes_filtered_for_generic_wrap_consume_transaction
        NewRelic::Agent::Messaging.wrap_message_broker_consume_transaction(
          library: "RabbitMQ",
          destination_type: :exchange,
          destination_name: "Default",
          attributes: {
            :'message.routingKey'    => 'red',
            :'message.exchangeType'  => 'fanout',
            :'message.queueName'     => 'some.queue',
            :'message.replyTo'       => 'reply.to.queue',
            :'message.correlationId' => 'abcdef12345',
            :'key.that.shouldnt.be'  => 'value.that.shouldnt.be'
          }
        ) {}

        event = last_transaction_event
        assert_equal "red", event[2][:'message.routingKey']
        assert_equal "fanout", event[2][:'message.exchangeType']
        assert_equal "some.queue", event[2][:'message.queueName']
        assert_equal "reply.to.queue", event[2][:'message.replyTo']
        assert_equal "abcdef12345", event[2][:'message.correlationId']
        refute event[2].key?(:'key.that.shouldnt.be'), "wrap_message_broker_consume_transaction should filter disallowed attributes"
      end

      def test_agent_attributes_not_assigned_when_in_transaction_but_not_subscribed
        in_transaction "test_txn" do
          message_properties = {headers: {foo: "bar"}, reply_to: "blue", correlation_id: "abc"}
          delivery_info      = {routing_key: "red", exchange_name: "foobar"}

          NewRelic::Agent::Messaging.start_amqp_consume_segment(
            library: "RabbitMQ",
            destination_name: "Default",
            delivery_info: delivery_info,
            message_properties: message_properties,
            queue_name: "yellow",
            exchange_type: "direct"
          )
        end

        event = last_transaction_event
        assert_equal nil, event[2][:"message.routingKey"]
      end

      def test_agent_attributes_not_assigned_when_not_subscribed_nor_in_transaction
        message_properties = {headers: {foo: "bar"}, reply_to: "blue", correlation_id: "abc"}
        delivery_info      = {routing_key: "red", exchange_name: "foobar"}

        segment = NewRelic::Agent::Messaging.start_amqp_consume_segment(
          library: "RabbitMQ",
          destination_name: "Default",
          delivery_info: delivery_info,
          message_properties: message_properties,
          queue_name: "yellow",
          exchange_type: "direct"
        )

        refute segment.transaction, "expected nil segment.transaction, actual: #{segment.transaction}"
        refute last_transaction_event, "expected nil last_transaction_event, actual: #{last_transaction_event}"
      end

      def test_consume_api_passes_message_properties_headers_to_underlying_api
        message_properties = {headers: {foo: "bar"}, reply_to: "blue", correlation_id: "abc"}
        delivery_info      = {routing_key: "red", exchange_name: "foobar"}

        segment = NewRelic::Agent::Messaging.start_amqp_consume_segment(
          library: "RabbitMQ",
          destination_name: "Default",
          delivery_info: delivery_info,
          message_properties: message_properties,
          queue_name: "yellow",
          exchange_type: "direct"
        )

        assert NewRelic::Agent::Transaction::MessageBrokerSegment === segment
        assert_equal message_properties[:headers], segment.message_properties
      end

      def test_start_message_broker_segments_returns_properly_constructed_segment
        segment = NewRelic::Agent::Transaction.start_message_broker_segment(
          action: :produce,
          library: "RabbitMQ",
          destination_type: :exchange,
          destination_name: "QQ"
        )

        assert NewRelic::Agent::Transaction::MessageBrokerSegment === segment
        assert_equal "MessageBroker/RabbitMQ/Exchange/Produce/Named/QQ", segment.name
        assert_equal :produce, segment.action
        assert_equal "RabbitMQ", segment.library
        assert_equal :exchange, segment.destination_type
        assert_equal "QQ", segment.destination_name
      end

      def test_headers_not_attached_to_segment_if_empty_on_produce
        segment = NewRelic::Agent::Messaging.start_amqp_publish_segment(
          library: "RabbitMQ",
          destination_name: "Default",
          headers: {}
        )
        refute segment.params[:headers], "expected no :headers key in segment params"
      end

      def test_headers_not_attached_to_segment_if_empty_on_consume
        segment = NewRelic::Agent::Messaging.start_amqp_consume_segment(
          library: "RabbitMQ",
          destination_name: "Default",
          delivery_info: {routing_key: "foo", exchange_name: "bar"},
          message_properties: {headers: {}}
        )
        refute segment.params[:headers], "expected no :headers key in segment params"
      end

      def test_consume_segments_filter_out_CAT_headers_from_parameters
        segment = NewRelic::Agent::Messaging.start_amqp_consume_segment(
          library: "RabbitMQ",
          destination_name: "Default",
          delivery_info: {routing_key: "foo", exchange_name: "bar"},
          message_properties: {headers: {'hi' => 'there', 'NewRelicID' => '123#456', 'NewRelicTransaction' => 'abcdef'}}
        )
        refute segment.params[:headers].key?('NewRelicID'), "expected segment params to not have CAT header 'NewRelicID'"
        refute segment.params[:headers].key?('NewRelicTransaction'), "expected segment params to not have CAT header 'NewRelicTransaction'"
        assert segment.params[:headers].key?('hi'), "expected segment params to have application defined headers"
        assert_equal 'there', segment.params[:headers]['hi']
      end

      def test_consume_segments_do_not_attach_empty_after_filtering_headers
        segment = NewRelic::Agent::Messaging.start_amqp_consume_segment(
          library: "RabbitMQ",
          destination_name: "Default",
          delivery_info: {routing_key: "foo", exchange_name: "bar"},
          message_properties: {headers: {'NewRelicID' => '123#456', 'NewRelicTransaction' => 'abcdef'}}
        )
        refute segment.params[:headers], "expected no :headers key in segment params"
      end

      def test_agent_attributes_assigned_for_amqp_wrap_consume_transaction
        tap = mock 'tap'
        tap.expects :tap

        NewRelic::Agent::Messaging.wrap_amqp_consume_transaction(
          library: "AwesomeBunniez",
          destination_name: "MyExchange",
          delivery_info: {routing_key: 'blue'},
          message_properties: {reply_to: 'reply.key', correlation_id: 'correlate'},
          exchange_type: :fanout,
          queue_name: 'some.queue',
        ) { tap.tap }

        event = last_transaction_event
        assert_equal "blue", event[2][:'message.routingKey']
        assert_equal "reply.key", event[2][:'message.replyTo']
        assert_equal "correlate", event[2][:'message.correlationId']
        assert_equal :fanout, event[2][:'message.exchangeType']
        assert_equal "some.queue", event[2][:'message.queueName']
      end
    end
  end
end
