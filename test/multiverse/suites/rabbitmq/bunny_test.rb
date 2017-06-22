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

  def teardown
    @chan.queue("hello").purge
    @conn.close
  end

  def test_metrics_recorded_for_produce_to_the_default_exchange
    queue  = @chan.queue("hello")
    in_transaction "test_txn" do
      queue.publish("test_msg")
    end
    assert_metrics_recorded [
      ["MessageBroker/RabbitMQ/Exchange/Produce/Named/Default", "test_txn"],
      "MessageBroker/RabbitMQ/Exchange/Produce/Named/Default"
    ]
  end

  def test_metrics_recorded_for_consume_from_the_default_exchange
    q = @chan.queue "hello"

    q.publish "test_msg"

    in_transaction "test_txn" do
      q.pop
    end

    assert_metrics_recorded [
      ["MessageBroker/RabbitMQ/Exchange/Consume/Named/Default", "test_txn"],
      "MessageBroker/RabbitMQ/Exchange/Consume/Named/Default"
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

  def test_metrics_recorded_for_consume_from_a_named_exchange
    x = @chan.fanout "activity.events"
    q = @chan.queue "hello"
    q.bind x

    x.publish "howdy", {
      routing_key: "red"
    }

    in_transaction "test_txn" do
      q.pop
    end

    assert_metrics_recorded [
      ["MessageBroker/RabbitMQ/Exchange/Consume/Named/activity.events", "test_txn"],
      "MessageBroker/RabbitMQ/Exchange/Consume/Named/activity.events"
    ]
  end

  def test_segment_parameters_recorded_for_produce
    x       = @chan.fanout "activity.events"
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

  def test_segment_parameters_recorded_for_consume
    q       = @chan.queue("hello")
    headers = {foo: "bar"}

    q.publish "howdy", {
      headers: headers,
      reply_to: "blue",
      correlation_id: "abc"
    }

    in_transaction "test_txn" do
      q.pop
    end

    node = find_node_with_name_matching last_transaction_trace, /^MessageBroker\//

    assert_equal :direct, node.params[:exchange_type]
    assert_equal "hello", node.params[:routing_key]
    assert_equal({"foo" => "bar"}, node.params[:headers])
    assert_equal "blue", node.params[:reply_to]
    assert_equal "abc", node.params[:correlation_id]
  end

  def test_pop_returns_original_message
    q = @chan.queue("hello")
    q.publish "howdy"
    msg = q.pop

    assert Array === msg, "message was not an array"
    assert Bunny::GetResponse === msg[0]
    assert Bunny::MessageProperties === msg[1]
    assert_equal "howdy", msg[2]
  end

  def test_error_starting_amqp_segment_does_not_interfere_with_transaction
    NewRelic::Agent::Transaction::MessageBrokerSegment.any_instance.stubs(:start).raises(StandardError.new("Boo"))
    queue  = @chan.queue("test1")
    in_transaction "test_txn" do
      #our instrumentation should error here, but not interfere with bunny
      queue.publish("test_msg")
       #this segment should be fine
      segment = NewRelic::Agent::Transaction.start_segment "Custom/blah/method"
      segment.finish
    end

    assert_metrics_recorded ["Custom/blah/method"]
    refute_metrics_recorded [
      "MessageBroker/RabbitMQ/Exchange/Produce/Named/Default"
    ]
  end

  def test_transaction_implicitly_created_for_consume
    lock = Mutex.new
    cond = ConditionVariable.new

    msg = nil
    queue = @chan.queue("QQ", :exclusive => true)

    queue.subscribe(:block => false) do |delivery_info, properties, payload|
      lock.synchronize do
        msg = payload
        cond.signal
      end
    end

    lock.synchronize do
      queue.publish "hi"
      cond.wait(lock)
    end

    # Even with the condition variable above there is a race condition between
    # when the subscribe block finishes and when the transaction is committed.
    # This gross code below is here to account for that. Also, we don't
    # ever expect to hit the max number of cycles, but we are being defensive so
    # that this test doesn't block indefinitely if something unexpected occurs.

    cycles = 0
    until (tt = last_transaction_trace) || cycles > 10
      sleep 0.1
      cycles += 1
    end

    assert_equal "hi", msg

    refute_nil tt, "Did not expect tt to be nil. Something terrible has occurred."

    trace_node = find_node_with_name_matching tt, /^MessageBroker/

    # expected parameters
    assert_equal "QQ", trace_node.params[:routing_key]
    assert_equal "QQ", trace_node.params[:queue_name]
    assert_equal :direct, trace_node[:exchange_type]

    # agent attributes
    expected_destinations =   NewRelic::Agent::AttributeFilter::DST_TRANSACTION_TRACER |
                              NewRelic::Agent::AttributeFilter::DST_TRANSACTION_EVENTS |
                              NewRelic::Agent::AttributeFilter::DST_ERROR_COLLECTOR

    assert_equal({:"message.routingKey"=>"QQ"}, tt.attributes.agent_attributes_for(expected_destinations))

    # metrics
    assert_metrics_recorded [
      ["MessageBroker/RabbitMQ/Exchange/Consume/Named/Default", "OtherTransaction/Message/RabbitMQ/Exchange/Named/Default"],
      "OtherTransaction/Message/RabbitMQ/Exchange/Named/Default",
      "MessageBroker/RabbitMQ/Exchange/Consume/Named/Default"
    ]
  end

  def test_metrics_recorded_for_purge
    queue  = @chan.queue("test")

    in_transaction "test_txn" do
      queue.publish "test"
      queue.purge
    end

    assert_metrics_recorded "MessageBroker/RabbitMQ/Queue/Purge/Named/test"
  end
end
