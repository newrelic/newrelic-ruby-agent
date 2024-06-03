# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class AwssqsInstrumentationTest < Minitest::Test
  def setup
    Aws.config.update(stub_responses: true)
    @stats_engine = NewRelic::Agent.instance.stats_engine
  end

  def teardown
    mocha_teardown
    NewRelic::Agent.instance.stats_engine.clear_stats
  end

  def create_client
    Aws::SQS::Client.new(region: 'us-east-2')
  end

  def test_all_attributes_added_to_segment_send_message
    client = create_client

    in_transaction do |txn|
      client.send_message({
        queue_url: 'https://sqs.us-east-2.amazonaws.com/123456789/itsatestqueuewow',
        message_body: 'wow, its a message'
      })
    end

    spans = harvest_span_events!
    span = spans[1][0]

    assert_equal 'MessageBroker/SQS/Queue/Produce/Named/itsatestqueuewow', span[0]['name']

    assert_equal 'aws_sqs', span[2]['messaging.system']
    assert_equal 'us-east-2', span[2]['cloud.region']
    assert_equal '123456789', span[2]['cloud.account.id']
    assert_equal 'itsatestqueuewow', span[2]['messaging.destination.name']
  end

  def test_all_attributes_added_to_segment_send_message_batch
    client = create_client

    in_transaction do |txn|
      client.send_message_batch({
        queue_url: 'https://sqs.us-east-2.amazonaws.com/123456789/itsatestqueuewow',
        entries: [
          {
            id: "msq1", 
            message_body: "wow 1", 
          },
          {
            id: "msq2", 
            message_body: "wow 2", 
          }
        ]
      })
    end

    spans = harvest_span_events!
    span = spans[1][0]

    assert_equal 'MessageBroker/SQS/Queue/Produce/Named/itsatestqueuewow', span[0]['name']

    assert_equal 'aws_sqs', span[2]['messaging.system']
    assert_equal 'us-east-2', span[2]['cloud.region']
    assert_equal '123456789', span[2]['cloud.account.id']
    assert_equal 'itsatestqueuewow', span[2]['messaging.destination.name']
  end
  def test_all_attributes_added_to_segment_receive_message
    client = create_client

    in_transaction do |txn|
      client.receive_message({
        queue_url: 'https://sqs.us-east-2.amazonaws.com/123456789/itsatestqueuewow'
      })
    end

    spans = harvest_span_events!
    span = spans[1][0]

    assert_equal 'MessageBroker/SQS/Queue/Consume/Named/itsatestqueuewow', span[0]['name']

    assert_equal 'aws_sqs', span[2]['messaging.system']
    assert_equal 'us-east-2', span[2]['cloud.region']
    assert_equal '123456789', span[2]['cloud.account.id']
    assert_equal 'itsatestqueuewow', span[2]['messaging.destination.name']
  end

  # Add tests here
end
