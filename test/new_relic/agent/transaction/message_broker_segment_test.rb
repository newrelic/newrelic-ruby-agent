# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../../test_helper', __FILE__)

require 'new_relic/agent/transaction'

module NewRelic
  module Agent
    class Transaction
      class MessageBrokerSegmentTest < Minitest::Test
        def test_segment_recorded_in_txn
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
          with_config :"cross_application_tracer.enabled" => true, :cross_process_id => "321#123", :encoding_key => "abc" do

            in_transaction "test_txn" do |txn|
              obfuscated_id = obfuscator.obfuscate "321#123"
              raw_txn_info = [txn.guid, false, txn.guid, txn.cat_path_hash(txn.state)]
              obfuscated_txn_info = obfuscator.obfuscate raw_txn_info.to_json

              NewRelic::Agent::Transaction.start_message_broker_segment(
                action: :consume,
                library: "RabbitMQ",
                destination_type: :exchange,
                destination_name: "Default",
                message_properties: {"NewRelicID" => obfuscated_id, "NewRelicTransaction" => obfuscated_txn_info }
              )

              assert_equal "321#123", txn.state.client_cross_app_id
              assert_equal raw_txn_info, txn.state.referring_transaction_info
            end
          end
        end

        def test_segment_reads_synthetics_and_cat_headers_from_message_properties_for_consume
          with_config :"cross_application_tracer.enabled" => true, :cross_process_id => "321#123", :encoding_key => "abc" do

            in_transaction "test_txn" do |txn|
              obfuscated_id = obfuscator.obfuscate "321#123"
              raw_txn_info = [txn.guid, false, txn.guid, txn.cat_path_hash(txn.state)]
              obfuscated_txn_info = obfuscator.obfuscate raw_txn_info.to_json

              NewRelic::Agent::Transaction.start_message_broker_segment(
                action: :consume,
                library: "RabbitMQ",
                destination_type: :exchange,
                destination_name: "Default",
                message_properties: {"NewRelicID" => obfuscated_id, "NewRelicTransaction" => obfuscated_txn_info, "NewRelicSynthetics" => "boo" }
              )

              assert_equal "321#123", txn.state.client_cross_app_id
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
