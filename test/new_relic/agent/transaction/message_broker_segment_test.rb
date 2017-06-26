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
                message_properties: {}
              )

              assert segment.message_properties.key?("NewRelicID"), "Expected message_properties to contain: NewRelicId"
              assert segment.message_properties.key?("NewRelicTransaction"), "Expected message_properties to contain: NewRelicTransaction"
              refute segment.message_properties.key?("NewRelicSynthetics")
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
                message_properties: {}
              )

              assert segment.message_properties.key?("NewRelicID"), "Expected message_properties to contain: NewRelicId"
              assert segment.message_properties.key?("NewRelicTransaction"), "Expected message_properties to contain: NewRelicTransaction"
              assert segment.message_properties.key?("NewRelicSynthetics"), "Expected message_properties to contain: NewRelicSynthetics"
            end
          end
        end

        def test_segment_reads_cat_headers_from_message_properties_for_consume
          guid                 = "BEC1BC64675138B9"
          cross_process_id     = "321#123"
          intrinsic_attributes = { client_cross_process_id: cross_process_id, referring_transaction_guid: guid }

          with_config :"cross_application_tracer.enabled" => true, :cross_process_id => cross_process_id, :encoding_key => "abc" do

            in_transaction "test_txn" do |txn|
              obfuscated_id = obfuscator.obfuscate cross_process_id
              raw_txn_info = [guid, false, guid, txn.cat_path_hash(txn.state)]
              obfuscated_txn_info = obfuscator.obfuscate raw_txn_info.to_json

              NewRelic::Agent::Transaction.start_message_broker_segment(
                action: :consume,
                library: "RabbitMQ",
                destination_type: :exchange,
                destination_name: "Default",
                message_properties: {"NewRelicID" => obfuscated_id, "NewRelicTransaction" => obfuscated_txn_info }
              )

              assert_equal cross_process_id, txn.state.client_cross_app_id
              assert_equal raw_txn_info, txn.state.referring_transaction_info
              assert_equal txn.attributes.intrinsic_attributes_for(NewRelic::Agent::AttributeFilter::DST_TRANSACTION_TRACER), intrinsic_attributes
            end
          end
        end

        def test_segment_records_proper_metrics_for_consume_with_cat
          guid                 = "BEC1BC64675138B9"
          cross_process_id     = "321#123"

          with_config :"cross_application_tracer.enabled" => true, :cross_process_id => cross_process_id, :encoding_key => "abc" do

            in_transaction "test_txn" do |txn|
              obfuscated_id = obfuscator.obfuscate cross_process_id
              raw_txn_info = [guid, false, guid, txn.cat_path_hash(txn.state)]
              obfuscated_txn_info = obfuscator.obfuscate raw_txn_info.to_json

              NewRelic::Agent::Transaction.start_message_broker_segment(
                action: :consume,
                library: "RabbitMQ",
                destination_type: :exchange,
                destination_name: "Default",
                message_properties: {"NewRelicID" => obfuscated_id, "NewRelicTransaction" => obfuscated_txn_info }
              )
            end

            assert_metrics_recorded [
              ["MessageBroker/RabbitMQ/Exchange/Consume/Named/Default", "test_txn"],
              "MessageBroker/RabbitMQ/Exchange/Consume/Named/Default",
              "ClientApplication/#{cross_process_id}/all"
            ]
          end
        end

        def test_segment_reads_synthetics_and_cat_headers_from_message_properties_for_consume
          cross_process_id = "321#123"
          guid             = "BEC1BC64675138B9"

          with_config :"cross_application_tracer.enabled" => true, :cross_process_id => "321#123", :encoding_key => "abc" do

            in_transaction "test_txn" do |txn|
              obfuscated_id = obfuscator.obfuscate cross_process_id
              raw_txn_info = [guid, false, guid, txn.cat_path_hash(txn.state)]
              obfuscated_txn_info = obfuscator.obfuscate raw_txn_info.to_json

              NewRelic::Agent::Transaction.start_message_broker_segment(
                action: :consume,
                library: "RabbitMQ",
                destination_type: :exchange,
                destination_name: "Default",
                message_properties: {"NewRelicID" => obfuscated_id, "NewRelicTransaction" => obfuscated_txn_info, "NewRelicSynthetics" => "boo" }
              )

              assert_equal cross_process_id, txn.state.client_cross_app_id
              assert_equal raw_txn_info, txn.state.referring_transaction_info
              assert_equal "boo", txn.raw_synthetics_header
            end
          end
        end

        def obfuscator
          NewRelic::Agent::Transaction::MessageBrokerSegment.obfuscator
        end
      end
    end
  end
end
