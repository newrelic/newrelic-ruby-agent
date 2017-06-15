# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class BunnyTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent do
    @conn = Bunny.new
    @conn.start
    @chan = @conn.create_channel
  end

  def test_metrics_recorded_for_produce_to_the_default_exchange
    queue  = @chan.queue("test1")
    in_transaction "test_txn" do
      queue.publish("test_msg")
    end
    assert_metrics_recorded [
      ["MessageBroker/RabbitMQ/Exchange/Produce/Named/Default", "test_txn"],
      "MessageBroker/RabbitMQ/Exchange/Produce/Named/Default"
    ]
  end

  def test_metrics_recorded_for_produce_to_a_named_exchange
    x = Bunny::Exchange.new @chan, :fanout, "activity.events"
    in_transaction "test_txn" do
      x.publish "hi"
    end
    assert_metrics_recorded [
      ["MessageBroker/RabbitMQ/Exchange/Produce/Named/activity.events", "test_txn"],
      "MessageBroker/RabbitMQ/Exchange/Produce/Named/activity.events"
    ]
  end

  def test_segment_parameters_recorded_for_produce
    x = Bunny::Exchange.new @chan, :fanout, "activity.events"
    headers = {foo: "bar"}
    in_transaction "test_txn" do
      x.publish "howdy", {
        routing_key: "red",
        headers: headers,
        reply_to: "blue",
        correlation_id: "abc"
      }
    end

    node = find_node_with_name_matching last_transaction_trace, /^MessageBroker\//

    assert_equal :fanout, node.params[:exchange_type]
    assert_equal "red", node.params[:routing_key]
    assert_equal headers, node.params[:headers]
    assert_equal "blue", node.params[:reply_to]
    assert_equal "abc", node.params[:correlation_id]
  end
end
