# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'aws-sdk-dynamodb'

class DynamodbInstrumentationTest < Minitest::Test
  def setup
    Aws.config.update(stub_responses: true)
    @stats_engine = NewRelic::Agent.instance.stats_engine
  end

  def teardown
    mocha_teardown
    NewRelic::Agent.instance.stats_engine.clear_stats
  end

  def create_client
    Aws::DynamoDB::Client.new(region: 'us-east-2')
  end

  def test_all_attributes_added_to_segment
    client = create_client
    Seahorse::Client::Http::Response.any_instance.stubs(:headers).returns({'x-amzn-requestid' => '1234321'})
    NewRelic::Agent::Aws.stubs(:create_arn).returns('test-arn')

    in_transaction do |txn|
      client.query({
        expression_attribute_values: {':v1' => 'value'},
        table_name: 'test-table'
      })
      @segment = txn.segments[1]
    end

    assert_equal NewRelic::Agent::Transaction::DatastoreSegment, @segment.class
    assert_equal 'query', @segment.operation
    assert_equal 'DynamoDB', @segment.product
    assert_equal 'test-table', @segment.collection
    assert_equal 'dynamodb.us-east-2.amazonaws.com', @segment.host
    assert_equal 'us-east-2', @segment.attributes.agent_attributes_for(NewRelic::Agent::AttributeFilter::DST_SPAN_EVENTS)['aws.region']
    assert_equal 'query', @segment.attributes.agent_attributes_for(NewRelic::Agent::AttributeFilter::DST_SPAN_EVENTS)['aws.operation']
    assert_equal '1234321', @segment.attributes.agent_attributes_for(NewRelic::Agent::AttributeFilter::DST_SPAN_EVENTS)['aws.requestId']
    assert_equal 'test-arn', @segment.attributes.agent_attributes_for(NewRelic::Agent::AttributeFilter::DST_SPAN_EVENTS)['cloud.resource_id']
  end

  def test_create_table_table_name_operation
    client = create_client

    in_transaction do |txn|
      client.create_table({
        attribute_definitions: [
          {
            attribute_name: 'attr_name',
            attribute_type: 'S'
          }
        ],
        key_schema: [
          {
            attribute_name: 'attr_name',
            key_type: 'HASH'
          }
        ],
        table_name: 'test-table'
      })
      @segment = txn.segments[1]
    end

    assert_equal 'test-table', @segment.collection
    assert_equal 'create_table', @segment.operation
  end

  def test_delete_item_table_name_operation
    client = create_client
    in_transaction do |txn|
      client.delete_item({
        key: {
          'key_name' => {
            s: 'key_value'
          }
        },
        table_name: 'test-table'
      })
      @segment = txn.segments[1]
    end

    assert_equal 'test-table', @segment.collection
    assert_equal 'delete_item', @segment.operation
  end

  def test_delete_table_table_name_operation
    client = create_client
    in_transaction do |txn|
      client.delete_table({
        table_name: 'test-table'
      })
      @segment = txn.segments[1]
    end

    assert_equal 'test-table', @segment.collection
    assert_equal 'delete_table', @segment.operation
  end

  def test_get_item_table_name_operation
    client = create_client
    in_transaction do |txn|
      client.get_item({
        key: {
          'key_name' => {
            s: 'key_value'
          }
        },
        table_name: 'test-table'
      })
      @segment = txn.segments[1]
    end

    assert_equal 'test-table', @segment.collection
    assert_equal 'get_item', @segment.operation
  end

  def test_put_item_table_name_operation
    client = create_client
    in_transaction do |txn|
      client.put_item({
        item: {
          'key_name' => {
            s: 'key_value'
          }
        },
        table_name: 'test-table'
      })
      @segment = txn.segments[1]
    end

    assert_equal 'test-table', @segment.collection
    assert_equal 'put_item', @segment.operation
  end

  def test_query_table_name_operation
    client = create_client

    in_transaction do |txn|
      client.query({
        expression_attribute_values: {':v1' => 'value'},
        table_name: 'test-table'
      })
      @segment = txn.segments[1]
    end

    assert_equal 'test-table', @segment.collection
    assert_equal 'query', @segment.operation
  end

  def test_scan_table_name_operation
    client = create_client
    in_transaction do |txn|
      client.scan({
        expression_attribute_names: {
          '#KN' => 'AlbumTitle'
        },
        filter_expression: 'key_name = :a',
        table_name: 'test-table'
      })
      @segment = txn.segments[1]
    end

    assert_equal 'test-table', @segment.collection
    assert_equal 'scan', @segment.operation
  end

  def test_update_item_table_name_operation
    client = create_client
    in_transaction do |txn|
      client.update_item({
        key: {
          'key_name' => 'value1'
        },
        attribute_updates: {
          'key_name' => {
            value: 'value2',
            action: 'ADD'
          }
        },
        table_name: 'test-table'
      })
      @segment = txn.segments[1]
    end

    assert_equal 'test-table', @segment.collection
    assert_equal 'update_item', @segment.operation
  end
end
