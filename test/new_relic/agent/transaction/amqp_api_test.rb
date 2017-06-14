# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../../test_helper', __FILE__)

require 'new_relic/agent/transaction'

module NewRelic
  module Agent
    class Transaction
      class AMQPAPITest < Minitest::Test
        def test_metrics_recorded_for_amqp_segment
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
      end
    end
  end
end
