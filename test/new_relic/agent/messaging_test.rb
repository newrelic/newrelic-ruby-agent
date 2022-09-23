# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
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
        in_transaction("test_txn") do
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
        in_transaction("test_txn") do
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
        in_transaction("test_txn") do
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

      def test_segment_params_not_recorded_for_publish_with_segment_params_disabled
        with_config(:'message_tracer.segment_parameters.enabled' => false) do
          in_transaction("test_txn") do
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

            refute segment.params.has_key?(:routing_key), "Params should not have key :routing_key"
            refute segment.params.has_key?(:headers), "Params should not have key :headers"
            refute segment.params.has_key?(:reply_to), "Params should not have key :reply_to"
            refute segment.params.has_key?(:correlation_id), "Params should not have key :correlation_id"
            refute segment.params.has_key?(:exchange_type), "Params should not have key :exchange_type"
          end
        end
      end

      def test_segment_parameters_recorded_for_consume
        in_transaction("test_txn") do
          message_properties = {headers: {foo: "bar"}, reply_to: "blue", correlation_id: "abc"}
          delivery_info = {routing_key: "red", exchange_name: "foobar"}

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

      def test_segment_params_not_recorded_for_consume_with_segment_params_disabled
        with_config(:'message_tracer.segment_parameters.enabled' => false) do
          in_transaction("test_txn") do
            message_properties = {headers: {foo: "bar"}, reply_to: "blue", correlation_id: "abc"}
            delivery_info = {routing_key: "red", exchange_name: "foobar"}

            segment = NewRelic::Agent::Messaging.start_amqp_consume_segment(
              library: "RabbitMQ",
              destination_name: "Default",
              delivery_info: delivery_info,
              message_properties: message_properties,
              queue_name: "yellow",
              exchange_type: "direct"
            )

            refute segment.params.has_key?(:routing_key), "Params should not have key :routing_key"
            refute segment.params.has_key?(:headers), "Params should not have key :headers"
            refute segment.params.has_key?(:reply_to), "Params should not have key :reply_to"
            refute segment.params.has_key?(:correlation_id), "Params should not have key :correlation_id"
            refute segment.params.has_key?(:exchange_type), "Params should not have key :exchange_type"
          end
        end
      end

      def test_wrap_message_broker_consume_transaction
        tap = mock('tap')
        tap.expects(:tap)

        NewRelic::Agent::Messaging.wrap_message_broker_consume_transaction(
          library: "AwesomeBunniez",
          destination_type: :exchange,
          destination_name: "Default",
          routing_key: "red"
        ) do
          txn = NewRelic::Agent::Tracer.current_transaction
          assert_equal 'OtherTransaction/Message/AwesomeBunniez/Exchange/Named/Default', txn.best_name
          tap.tap
        end

        txn = last_transaction_trace
        assert txn.finished, "Expected transaction to be finished"
      end

      def test_agent_attributes_assigned_for_generic_wrap_consume_transaction
        NewRelic::Agent.instance.span_event_aggregator.stubs(:enabled?).returns(true)
        NewRelic::Agent::Transaction.any_instance.stubs(:sampled?).returns(true)

        tap = mock('tap')
        tap.expects(:tap)

        NewRelic::Agent::Messaging.wrap_message_broker_consume_transaction(
          library: "RabbitMQ",
          destination_type: :exchange,
          destination_name: "Default",
          routing_key: "red"
        ) { tap.tap }

        transaction_event = last_transaction_event
        assert Array === transaction_event, "expected Array, actual: #{transaction_event.class}"
        assert_equal 3, transaction_event.length, "expected Array of 3 elements, actual: #{transaction_event.length}"
        assert transaction_event.all?(Hash), "expected Array of 3 hashes, actual: [#{transaction_event.map(&:class).join(',')}]"
        assert transaction_event[2].key?(:'message.routingKey'), "expected transaction event attributes to have key :'message.routingKey', actual: #{transaction_event[2].keys.join(',')}"
        assert_equal "red", transaction_event[2][:'message.routingKey']

        span_event = last_span_event
        assert span_event[2].key?(:'message.routingKey'), "expected span event attributes to have key :'message.routingKey', actual: #{span_event[2].keys.join(',')}"
        assert_equal "red", span_event[2][:'message.routingKey']
      end

      def test_header_attributes_assigned_for_generic_wrap_consume_transaction
        with_config(:"attributes.include" => "message.headers.*") do
          tap = mock('tap')
          tap.expects(:tap)

          NewRelic::Agent::Messaging.wrap_message_broker_consume_transaction(
            library: "RabbitMQ",
            destination_type: :exchange,
            destination_name: "Default",
            routing_key: "red",
            headers: {token: "foo"}
          ) { tap.tap }

          event = last_transaction_event
          assert_equal "foo", event[2][:"message.headers.token"], "Expected header attributes to be added, actual attributes: #{event[2]}"
        end
      end

      def test_cat_headers_removed_when_headers_assigned_as_attributes
        with_config(:"attributes.include" => "message.headers.*") do
          tap = mock('tap')
          tap.expects(:tap)

          NewRelic::Agent::Messaging.wrap_message_broker_consume_transaction(
            library: "RabbitMQ",
            destination_type: :exchange,
            destination_name: "Default",
            routing_key: "red",
            headers: {"token" => "foo", "NewRelicID" => "bar"}
          ) { tap.tap }

          event = last_transaction_event
          refute event[2].has_key?(:"message.headers.NewRelicID"), "Expected CAT headers to be omitted from message attributes"
        end
      end

      def test_header_attributes_not_assigned_when_headers_not_included_in_consume_transaction
        tap = mock('tap')
        tap.expects(:tap)

        NewRelic::Agent::Messaging.wrap_message_broker_consume_transaction(
          library: "RabbitMQ",
          destination_type: :exchange,
          destination_name: "Default",
          routing_key: "red",
          headers: {token: "foo"}
        ) { tap.tap }

        event = last_transaction_event
        refute event[2].has_key?(:"message.headers.token"), "Expected header attributes not to be added"
      end

      def test_agent_attributes_not_assigned_when_in_transaction_but_not_subscribed
        NewRelic::Agent::Transaction.any_instance.stubs(:sampled?).returns(true)
        NewRelic::Agent.instance.span_event_aggregator.stubs(:enabled?).returns(true)

        in_transaction("test_txn") do
          message_properties = {headers: {foo: "bar"}, reply_to: "blue", correlation_id: "abc"}
          delivery_info = {routing_key: "red", exchange_name: "foobar"}

          segment = NewRelic::Agent::Messaging.start_amqp_consume_segment(
            library: "RabbitMQ",
            destination_name: "Default",
            delivery_info: delivery_info,
            message_properties: message_properties,
            queue_name: "yellow",
            exchange_type: "direct"
          )

          segment.finish
        end

        transaction_event = last_transaction_event
        assert_nil transaction_event[2][:"message.routingKey"]

        span_event = last_span_event
        assert_nil span_event[2][:"message.routingKey"]
      end

      def test_agent_attributes_not_assigned_when_not_subscribed_nor_in_transaction
        message_properties = {headers: {foo: "bar"}, reply_to: "blue", correlation_id: "abc"}
        delivery_info = {routing_key: "red", exchange_name: "foobar"}

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
        delivery_info = {routing_key: "red", exchange_name: "foobar"}

        segment = NewRelic::Agent::Messaging.start_amqp_consume_segment(
          library: "RabbitMQ",
          destination_name: "Default",
          delivery_info: delivery_info,
          message_properties: message_properties,
          queue_name: "yellow",
          exchange_type: "direct"
        )

        assert NewRelic::Agent::Transaction::MessageBrokerSegment === segment
        assert_equal message_properties[:headers], segment.headers
      end

      def test_start_message_broker_segments_returns_properly_constructed_segment
        segment = NewRelic::Agent::Tracer.start_message_broker_segment(
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

      def test_consume_segments_filter_out_synthetics_headers_from_parameters
        segment = NewRelic::Agent::Messaging.start_amqp_consume_segment(
          library: "RabbitMQ",
          destination_name: "Default",
          delivery_info: {routing_key: "foo", exchange_name: "bar"},
          message_properties: {headers: {'hi' => 'there', 'NewRelicSynthetics' => 'abcdef12345'}}
        )
        refute segment.params[:headers].key?('NewRelicSynthetics'), "expected segment params to not have Synthetics header"
        assert segment.params[:headers].key?('hi'), "expected segment params to have application defined headers"
        assert_equal 'there', segment.params[:headers]['hi']
      end

      def test_consume_segments_do_not_attach_empty_after_filtering_headers
        segment = NewRelic::Agent::Messaging.start_amqp_consume_segment(
          library: "RabbitMQ",
          destination_name: "Default",
          delivery_info: {routing_key: "foo", exchange_name: "bar"},
          message_properties: {headers: {'NewRelicID' => '123#456', 'NewRelicTransaction' => 'abcdef', 'NewRelicSynthetics' => 'qwerasdfzxcv'}}
        )
        refute segment.params[:headers], "expected no :headers key in segment params"
      end

      def test_agent_attributes_assigned_for_amqp_wrap_consume_transaction
        NewRelic::Agent::Transaction.any_instance.stubs(:sampled?).returns(true)
        NewRelic::Agent.instance.span_event_aggregator.stubs(:enabled?).returns(true)

        with_config(:"attributes.include" => ["message.headers.*", "message.replyTo", "message.correlationId", "message.exchangeType"]) do
          tap = mock('tap')
          tap.expects(:tap)

          NewRelic::Agent::Messaging.wrap_amqp_consume_transaction(
            library: "AwesomeBunniez",
            destination_name: "MyExchange",
            delivery_info: {routing_key: 'blue'},
            message_properties: {reply_to: 'reply.key', correlation_id: 'correlate', headers: {"foo" => "bar", "NewRelicID" => "baz"}},
            exchange_type: :fanout,
            queue_name: 'some.queue'
          ) { tap.tap }

          transaction_event = last_transaction_event
          assert_equal "blue", transaction_event[2][:'message.routingKey']
          assert_equal "reply.key", transaction_event[2][:'message.replyTo']
          assert_equal "correlate", transaction_event[2][:'message.correlationId']
          assert_equal :fanout, transaction_event[2][:'message.exchangeType']
          assert_equal "some.queue", transaction_event[2][:'message.queueName']
          assert_equal "bar", transaction_event[2][:'message.headers.foo']
          refute transaction_event[2].has_key?(:'message.headers.NewRelicID')

          span_event = last_span_event
          assert_equal "blue", span_event[2][:'message.routingKey']
          assert_equal "reply.key", span_event[2][:'message.replyTo']
          assert_equal "correlate", span_event[2][:'message.correlationId']
          assert_equal :fanout, span_event[2][:'message.exchangeType']
          assert_equal "some.queue", span_event[2][:'message.queueName']
          assert_equal "bar", span_event[2][:'message.headers.foo']
          refute span_event[2].has_key?(:'message.headers.NewRelicID')
        end
      end

      def test_segment_records_proper_metrics_for_consume
        in_transaction("test_txn") do |txn|
          segment = NewRelic::Agent::Messaging.start_message_broker_segment(
            action: :consume,
            library: "RabbitMQ",
            destination_type: :exchange,
            destination_name: "Default"
          )
          segment.finish
        end

        assert_metrics_recorded [
          ["MessageBroker/RabbitMQ/Exchange/Consume/Named/Default", "test_txn"],
          "MessageBroker/RabbitMQ/Exchange/Consume/Named/Default"
        ]
      end

      def test_wrap_message_broker_consume_transaction_reads_cat_headers
        guid = "BEC1BC64675138B9"
        cross_process_id = "321#123"
        intrinsic_attributes = {client_cross_process_id: cross_process_id, referring_transaction_guid: guid}
        obfuscated_id = nil
        raw_txn_info = nil
        obfuscated_txn_info = nil

        tap = mock('tap')
        tap.expects(:tap)

        with_config(:"cross_application_tracer.enabled" => true,
          :cross_process_id => cross_process_id,
          :'distributed_tracing.enabled' => false,
          :trusted_account_ids => [321],
          :encoding_key => "abc") do
          in_transaction do |txn|
            obfuscated_id = obfuscator.obfuscate(cross_process_id)
            raw_txn_info = [guid, false, guid, txn.distributed_tracer.cat_path_hash]
            obfuscated_txn_info = obfuscator.obfuscate(raw_txn_info.to_json)
          end

          NewRelic::Agent::Messaging.wrap_message_broker_consume_transaction(
            library: "RabbitMQ",
            destination_type: :exchange,
            destination_name: 'Default',
            headers: {"NewRelicID" => obfuscated_id, "NewRelicTransaction" => obfuscated_txn_info}
          ) do
            txn = NewRelic::Agent::Tracer.current_transaction
            payload = txn.distributed_tracer.cross_app_payload
            assert_equal cross_process_id, payload.id
            assert_equal payload.referring_guid, raw_txn_info[0]
            assert_equal payload.referring_trip_id, raw_txn_info[2]
            assert_equal payload.referring_path_hash, raw_txn_info[3]
            assert_equal txn.attributes.intrinsic_attributes_for(NewRelic::Agent::AttributeFilter::DST_TRANSACTION_TRACER), intrinsic_attributes
            tap.tap
          end
        end
      end

      def test_wrap_message_broker_consume_transaction_records_proper_metrics_with_cat
        guid = "BEC1BC64675138B9"
        cross_process_id = "321#123"
        obfuscated_id = nil
        raw_txn_info = nil
        obfuscated_txn_info = nil

        tap = mock('tap')
        tap.expects(:tap)

        with_config(:"cross_application_tracer.enabled" => true,
          :cross_process_id => cross_process_id,
          :'distributed_tracing.enabled' => false,
          :trusted_account_ids => [321],
          :encoding_key => "abc") do
          in_transaction("test_txn") do |txn|
            obfuscated_id = obfuscator.obfuscate(cross_process_id)
            raw_txn_info = [guid, false, guid, txn.distributed_tracer.cat_path_hash]
            obfuscated_txn_info = obfuscator.obfuscate(raw_txn_info.to_json)
          end

          Messaging.wrap_message_broker_consume_transaction(
            library: "RabbitMQ",
            destination_type: :exchange,
            destination_name: "Default",
            headers: {"NewRelicID" => obfuscated_id, "NewRelicTransaction" => obfuscated_txn_info}
          ) do
            tap.tap
          end

          assert_metrics_recorded "ClientApplication/#{cross_process_id}/all"
        end
      end

      def obfuscator
        NewRelic::Agent::CrossAppTracing.obfuscator
      end
    end
  end
end
