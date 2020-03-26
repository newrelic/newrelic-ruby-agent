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
    @conn.close
  end

  def test_metrics_recorded_for_produce_to_the_default_exchange
    with_queue do |queue|
      in_transaction "test_txn" do
        queue.publish("test_msg")
      end
      assert_metrics_recorded [
        ["MessageBroker/RabbitMQ/Exchange/Produce/Named/Default", "test_txn"],
        "MessageBroker/RabbitMQ/Exchange/Produce/Named/Default"
      ]
    end
  end

  def test_metrics_recorded_for_consume_from_the_default_exchange
    with_queue do |queue|
      queue.publish "test_msg"

      in_transaction "test_txn" do
        queue.pop
      end

      assert_metrics_recorded [
        ["MessageBroker/RabbitMQ/Exchange/Consume/Named/Default", "test_txn"],
        "MessageBroker/RabbitMQ/Exchange/Consume/Named/Default"
      ]
    end
  end

  def test_cat_headers_not_read_for_pop_by_default
    cross_process_id     = "321#123"

    with_queue do |queue|
      with_config :"cross_application_tracer.enabled" => true, :cross_process_id => cross_process_id, :encoding_key => "abc" do
        in_transaction "first_txn" do
          queue.publish "test_msg"
        end

        in_transaction "test_txn" do
          queue.pop
        end

        event = last_transaction_event

        refute event[0].has_key?("nr.guid"), "Event should not have key 'nr.guid'"
        refute event[0].has_key?("nr.referringTransactionGuid"), "Event should not have key 'nr.referringTransactionGuid'"
        refute event[0].has_key?("nr.tripId"), "Event should not have key 'nr.tripId'"
        refute event[0].has_key?("nr.pathHash"), "Event should not have key 'nr.pathHash'"
        refute event[0].has_key?("nr.referringPathHash"), "Event should not have key 'nr.referringPathHash'"

        assert_metrics_not_recorded ["ClientApplication/#{cross_process_id}/all"]
      end
    end
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

    with_queue do |queue|
      queue.bind x

      x.publish "howdy", {
        routing_key: "red"
      }

      in_transaction "test_txn" do
        queue.pop
      end

      assert_metrics_recorded [
        ["MessageBroker/RabbitMQ/Exchange/Consume/Named/activity.events", "test_txn"],
        "MessageBroker/RabbitMQ/Exchange/Consume/Named/activity.events"
      ]
    end
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
    headers = {foo: "bar"}

    with_queue do |queue|
      queue.publish "howdy", {
        headers: headers,
        reply_to: "blue",
        correlation_id: "abc"
      }

      in_transaction "test_txn" do
        queue.pop
      end

      node = find_node_with_name_matching last_transaction_trace, /^MessageBroker\//

      assert_equal :direct, node.params[:exchange_type]
      assert_equal queue.name, node.params[:routing_key]
      assert_equal({"foo" => "bar"}, node.params[:headers])
      assert_equal "blue", node.params[:reply_to]
      assert_equal "abc", node.params[:correlation_id]
    end
  end

  def test_pop_returns_original_message
    with_queue do |queue|
      queue.publish "howdy"
      msg = queue.pop

      assert Array === msg, "message was not an array"
      assert Bunny::GetResponse === msg[0]
      assert Bunny::MessageProperties === msg[1]
      assert_equal "howdy", msg[2]
    end
  end

  def test_error_starting_amqp_segment_does_not_interfere_with_transaction
    NewRelic::Agent::Messaging.stubs(:start_amqp_publish_segment).raises(StandardError.new("Boo"))

    with_queue do |queue|
      in_transaction "test_txn" do
        #our instrumentation should error here, but not interfere with bunny
        queue.publish("test_msg")
         #this segment should be fine
        segment = NewRelic::Agent::Tracer.start_segment name: "Custom/blah/method"
        segment.finish if segment
      end

      assert_metrics_recorded ["Custom/blah/method"]
      refute_metrics_recorded [
        "MessageBroker/RabbitMQ/Exchange/Produce/Named/Default"
      ]
    end
  end

  def test_transaction_implicitly_created_for_consume
    lock = Mutex.new
    cond = ConditionVariable.new

    msg = nil
    exchange = @chan.direct('myDirectExchange')

    with_config :'attributes.include' => ['message.exchangeType'] do
      with_queue do |queue|
        queue.bind(exchange, routing_key: 'some.key')

        queue.subscribe(:block => false) do |delivery_info, properties, payload|
          lock.synchronize do
            msg = payload
            cond.signal
          end
        end

        lock.synchronize do
          exchange.publish "hi", routing_key: 'some.key'
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

        expected_destinations =   NewRelic::Agent::AttributeFilter::DST_TRANSACTION_TRACER |
                                  NewRelic::Agent::AttributeFilter::DST_TRANSACTION_EVENTS |
                                  NewRelic::Agent::AttributeFilter::DST_ERROR_COLLECTOR

        assert_equal({ :"message.routingKey" => "some.key",
                       :"message.queueName" => queue.name,
                       :"message.exchangeType" => :direct,
                     },
                     tt.attributes.agent_attributes_for(expected_destinations))

        # metrics
        assert_metrics_recorded ["OtherTransaction/Message/RabbitMQ/Exchange/Named/myDirectExchange"]
      end
    end
  end

  def test_metrics_recorded_for_purge_with_server_named_queue
    with_queue do |queue|

      in_transaction "test_txn" do
        queue.publish "test"
        queue.purge
      end

      assert_metrics_recorded "MessageBroker/RabbitMQ/Queue/Purge/Temp"
    end
  end

  def test_metrics_recorded_for_purge_with_named_queue
    with_queue false do |queue|
      in_transaction "test_txn" do
        queue.publish "test"
        queue.purge
      end

      assert_metrics_recorded "MessageBroker/RabbitMQ/Queue/Purge/Named/#{queue.name}"
    end
  end

  def test_noticed_error_at_segment_and_txn_on_error
    txn = nil
    begin
      with_queue false do |queue|
        Bunny::Channel.any_instance.stubs("basic_get").raises(Timeout::Error)
        in_transaction do |msg_txn|
          txn = msg_txn
          queue.publish "test"
          queue.pop
        end
      end
    rescue StandardError => e
      # NOP -- allowing span and transaction to notice error
    end

    assert_segment_noticed_error txn, /^MessageBroker\/RabbitMQ/, "Timeout::Error", /timeout/i
    assert_transaction_noticed_error txn, "Timeout::Error"
  end

  def test_noticed_error_only_at_segment_on_error
    txn = nil
    with_queue false do |queue|
      Bunny::Channel.any_instance.stubs("basic_get").raises(Timeout::Error)
      in_transaction do |msg_txn|
        begin
          txn = msg_txn
          queue.publish "test"
          queue.pop
        rescue StandardError => e
          # NOP -- allowing ONLY span to notice error
        end
      end
    end

    assert_segment_noticed_error txn, /^MessageBroker\/RabbitMQ/, "Timeout::Error", /timeout/i
    refute_transaction_noticed_error txn, "Timeout::Error"
  end


  def test_error_starting_message_broker_segment_does_not_interfere_with_transaction
    with_queue do |queue|
      NewRelic::Agent::Tracer.stubs(:start_message_broker_segment).raises(StandardError.new("Boo"))

      in_transaction "test_txn" do
        # This should error
        queue.publish "test_msg"

        #this segment should be fine
        segment = NewRelic::Agent::Tracer.start_segment name: "Custom/blah/method"
        segment.finish
      end

      msg = queue.pop
      assert_equal "test_msg", msg[2]

      assert_metrics_recorded ["Custom/blah/method"]
      refute_metrics_recorded ["MessageBroker/RabbitMQ/Exchange/Produce/Named/Default"]
    end
  end

  def test_pop_returning_no_message_doesnt_error
    NewRelic::Agent.stubs(:logger).returns(NewRelic::Agent::MemoryLogger.new)

    with_queue do |queue|
      in_transaction "test_txn" do
        queue.pop
      end

      assert_empty NewRelic::Agent.logger.messages
    end
  end

  def test_pop_returning_a_good_message_send_to_an_exchange_we_havent_accessed_doesnt_error
    NewRelic::Agent.stubs(:logger).returns(NewRelic::Agent::MemoryLogger.new)

    with_queue do |queue|
      # publish in such a way that the exchange object does not end up in channel.exchanges
      channel = queue.channel
      channel.basic_publish("test_msg", "", queue.name)

      assert_empty channel.exchanges

      in_transaction "test_txn" do
        msg = queue.pop
        assert_equal "test_msg", msg[2]
      end

      assert_empty NewRelic::Agent.logger.messages

      assert_metrics_recorded ["MessageBroker/RabbitMQ/Exchange/Consume/Named/Default"]
    end
  end

  def with_queue temp=true, exclusive=true, &block
    queue_name = temp ? "" : random_string
    queue = @chan.queue(queue_name, exclusive: exclusive)

    yield queue if block_given?

    @chan.queue(queue.name).purge
  end

  def random_string
    Time.now.to_s
  end
end
