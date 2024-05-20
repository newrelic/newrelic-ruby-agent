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
    end

    spans = harvest_span_events!
    span = spans[1][0]

    assert_equal 'datastore', span[0]['category']
    assert_equal 'Datastore/statement/DynamoDB/test-table/query', span[0]['name']

    assert_equal 'dynamodb.us-east-2.amazonaws.com', span[2]['peer.hostname']
    assert_equal 'us-east-2', span[2]['aws.region']
    assert_equal 'query', span[2]['aws.operation']
    assert_equal '1234321', span[2]['aws.requestId']
    assert_equal 'test-arn', span[2]['cloud.resource_id']
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
    end

    spans = harvest_span_events!
    span = spans[1][0]

    assert_equal 'Datastore/statement/DynamoDB/test-table/create_table', span[0]['name']
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
    end

    spans = harvest_span_events!
    span = spans[1][0]

    assert_equal 'Datastore/statement/DynamoDB/test-table/delete_item', span[0]['name']
  end

  def test_delete_table_table_name_operation
    client = create_client
    in_transaction do |txn|
      client.delete_table({
        table_name: 'test-table'
      })
    end

    spans = harvest_span_events!
    span = spans[1][0]

    assert_equal 'Datastore/statement/DynamoDB/test-table/delete_table', span[0]['name']
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
    end

    spans = harvest_span_events!
    span = spans[1][0]

    assert_equal 'Datastore/statement/DynamoDB/test-table/get_item', span[0]['name']
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
    end

    spans = harvest_span_events!
    span = spans[1][0]

    assert_equal 'Datastore/statement/DynamoDB/test-table/put_item', span[0]['name']
  end

  def test_query_table_name_operation
    client = create_client

    in_transaction do |txn|
      client.query({
        expression_attribute_values: {':v1' => 'value'},
        table_name: 'test-table'
      })
    end

    spans = harvest_span_events!
    span = spans[1][0]

    assert_equal 'Datastore/statement/DynamoDB/test-table/query', span[0]['name']
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
    end

    spans = harvest_span_events!
    span = spans[1][0]

    assert_equal 'Datastore/statement/DynamoDB/test-table/scan', span[0]['name']
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
    end

    spans = harvest_span_events!
    span = spans[1][0]

    assert_equal 'Datastore/statement/DynamoDB/test-table/update_item', span[0]['name']
  end
end
