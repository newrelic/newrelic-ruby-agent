# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../../test_helper', __FILE__)

require 'new_relic/agent/transaction'

module NewRelic
  module Agent
    class Transaction
      class MessageBrokerSegmentTest < Minitest::Test
        def teardown
          NewRelic::Agent.drop_buffered_data
        end

        def test_metrics_recorded_for_produce
          in_transaction "test_txn" do
            segment = NewRelic::Agent::Transaction.start_message_broker_segment(
              action: :produce,
              library: "RabbitMQ",
              destination_type: :exchange,
              destination_name: "Default"
            )
            segment.finish
          end

          assert_metrics_recorded [
            ["MessageBroker/RabbitMQ/Exchange/Produce/Named/Default", "test_txn"],
            "MessageBroker/RabbitMQ/Exchange/Produce/Named/Default"
          ]
        end

        def test_metrics_recorded_for_consume
          in_transaction "test_txn" do
            segment = NewRelic::Agent::Transaction.start_message_broker_segment(
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

        def test_segment_copies_parameters
          in_transaction "test_txn" do
            segment = NewRelic::Agent::Transaction.start_message_broker_segment(
              action: :produce,
              library: "RabbitMQ",
              destination_type: :exchange,
              destination_name: "Default",
              parameters: {routing_key: "my.key", correlation_id: "123"}
            )

            assert_equal "my.key", segment.params[:routing_key]
            assert_equal "123", segment.params[:correlation_id]
          end
        end

        def test_segment_adds_cat_headers_to_message_properties_for_produce
          with_config :"cross_application_tracer.enabled" => true, :cross_process_id => "321#123", :encoding_key => "abc" do
            in_transaction "test_txn" do
              segment = NewRelic::Agent::Transaction.start_message_broker_segment(
                action: :produce,
                library: "RabbitMQ",
                destination_type: :exchange,
                destination_name: "Default",
                headers: {}
              )

              assert segment.headers.key?("NewRelicID"), "Expected message_properties to contain: NewRelicId"
              assert segment.headers.key?("NewRelicTransaction"), "Expected message_properties to contain: NewRelicTransaction"
              refute segment.headers.key?("NewRelicSynthetics")
            end
          end
        end

        def test_segment_adds_synthetics_and_cat_headers_to_message_properties_for_produce
          with_config :"cross_application_tracer.enabled" => true, :cross_process_id => "321#123", :encoding_key => "abc" do
            in_transaction "test_txn" do |txn|
              txn.raw_synthetics_header = "boo"

              segment = NewRelic::Agent::Transaction.start_message_broker_segment(
                action: :produce,
                library: "RabbitMQ",
                destination_type: :exchange,
                destination_name: "Default",
                headers: {}
              )

              assert segment.headers.key?("NewRelicID"), "Expected message_properties to contain: NewRelicId"
              assert segment.headers.key?("NewRelicTransaction"), "Expected message_properties to contain: NewRelicTransaction"
              assert segment.headers.key?("NewRelicSynthetics"), "Expected message_properties to contain: NewRelicSynthetics"
            end
          end
        end

        def test_sets_start_time_from_constructor
          t = Time.now

          segment = MessageBrokerSegment.new action: :produce,
                                             library: "RabbitMQ",
                                             destination_type: :exchange,
                                             destination_name: "Default",
                                             start_time: t
          assert_equal t, segment.start_time

          segment = NewRelic::Agent::Transaction.start_message_broker_segment action: :produce,
                                                                              library: "RabbitMQ",
                                                                              destination_type: :exchange,
                                                                              destination_name: "Default",
                                                                              start_time: t
          assert_equal t, segment.start_time
        end
      end
    end
  end
end
