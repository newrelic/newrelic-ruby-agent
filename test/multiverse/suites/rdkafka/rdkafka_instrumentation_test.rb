# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class RdkafkaInstrumentationTest < Minitest::Test
  def setup
    @topic = 'ruby-test-topic' + Time.now.to_i.to_s
    Rdkafka::Config.logger = Logger.new(STDOUT, level: :error)
    @stats_engine = NewRelic::Agent.instance.stats_engine
  end

  def teardown
    harvest_span_events!
    harvest_transaction_events!
    NewRelic::Agent.instance.stats_engine.clear_stats
    mocha_teardown
  end

  def test_produce_creates_span_metrics
    in_transaction do |txn|
      produce_message
    end

    spans = harvest_span_events!
    span = spans[1][0]

    assert_equal "MessageBroker/Kafka/Topic/Produce/Named/#{@topic}", span[0]['name']
    assert_metrics_recorded "MessageBroker/Kafka/Nodes/#{host}"
    assert_metrics_recorded "MessageBroker/Kafka/Nodes/#{host}/Produce/#{@topic}"
  end

  def test_consume_creates_span_metrics
    produce_message
    harvest_span_events!

    consumer = config.consumer
    consumer.subscribe(@topic)
    consumer.each do |message|
      # get 1 message and leave
      break
    end

    spans = harvest_span_events!
    span = spans[1][0]

    assert_equal "OtherTransaction/Message/Kafka/Topic/Consume/Named/#{@topic}", span[0]['name']
    assert_metrics_recorded "MessageBroker/Kafka/Nodes/#{host}"
    assert_metrics_recorded "MessageBroker/Kafka/Nodes/#{host}/Consume/#{@topic}"
  end

  def test_produce_with_different_host_key
    producer = config('metadata.broker.list').producer
    in_transaction do |txn|
      produce_message(producer)
    end

    spans = harvest_span_events!
    span = spans[1][0]

    assert_equal "MessageBroker/Kafka/Topic/Produce/Named/#{@topic}", span[0]['name']
    assert_metrics_recorded "MessageBroker/Kafka/Nodes/#{host}"
    assert_metrics_recorded "MessageBroker/Kafka/Nodes/#{host}/Produce/#{@topic}"
  end

  def test_consume_with_different_host_key
    produce_message
    harvest_span_events!

    consumer = config('metadata.broker.list').consumer
    consumer.subscribe(@topic)
    consumer.each do |message|
      # get 1 message and leave
      break
    end

    spans = harvest_span_events!
    span = spans[1][0]

    assert_equal "OtherTransaction/Message/Kafka/Topic/Consume/Named/#{@topic}", span[0]['name']
    assert_metrics_recorded "MessageBroker/Kafka/Nodes/#{host}"
    assert_metrics_recorded "MessageBroker/Kafka/Nodes/#{host}/Consume/#{@topic}"
  end

  def test_rdkafka_distributed_tracing
    NewRelic::Agent.agent.stub :connected?, true do
      with_config(account_id: '190', primary_application_id: '46954', trusted_account_key: 'trust_this!') do
        in_transaction('first_txn_for_dt') do |txn|
          produce_message
        end
      end
      first_txn = harvest_transaction_events![1]

      consumer = config.consumer
      consumer.subscribe(@topic)
      consumer.each do |message|
        # get 1 message and leave
        break
      end
      txn = harvest_transaction_events![1]

      assert_metrics_recorded 'Supportability/DistributedTrace/CreatePayload/Success'
      assert_equal txn[0][0]['traceId'], first_txn[0][0]['traceId']
      assert_equal txn[0][0]['parentId'], first_txn[0][0]['guid']
    end
  end

  def host
    '127.0.0.1:9092'
  end

  def config(host_key = 'bootstrap.servers')
    config_vals ||= {
      "#{host_key}": host,
      "group.id": 'ruby-test',
      'auto.offset.reset': 'smallest'
    }
    Rdkafka::Config.new(config_vals)
  end

  def produce_message(producer = config.producer)
    delivery_handles = []
    delivery_handles << producer.produce(
      topic: @topic,
      payload: 'Payload 1',
      key: 'Key 1'
    )
    delivery_handles.each(&:wait)
    producer.close
  end

  def mock_message(headers: {})
    message = mock
    message.stubs(:headers).returns(headers)
    message.stubs(:key).returns('Key 0')
    message.stubs(:offset).returns(7106)
    message.stubs(:partition).returns(0)
    message.stubs(:payload).returns('Payload 0')
    message.stubs(:timestamp).returns(Time.new(2024, 8, 21, 9, 52, 44, '-05:00'))
    message.stubs(:topic).returns('ruby-test-topic')
    message
  end
end
