# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../../test_helper', __FILE__)

require 'new_relic/agent/transaction'
require 'new_relic/agent/transaction/message_broker_segment'

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
      end
    end
  end
end
