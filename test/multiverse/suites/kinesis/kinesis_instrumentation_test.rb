# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'aws-sdk-kinesis'

class KinesisInstrumentationTest < Minitest::Test
  def setup
    Aws.config.update(stub_responses: true)
  end

  def teardown
    NewRelic::Agent.instance.stats_engine.clear_stats
  end

  def create_client
    Aws::Kinesis::Client.new(region: 'us-east-2')
  end

  def test_all_attributes_added_to_segment
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_stream({
          stream_name: 'deschutes_river',
          shard_count: 2
        })
      end

      spans = harvest_span_events!
      span = spans[1][0]

      assert_equal 'Kinesis/create_stream/deschutes_river', span[0]['name']
      assert_equal 'aws_kinesis_data_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_delete_stream
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_stream({
          stream_name: 'deschutes_river',
          shard_count: 2
        })

        client.delete_stream({
          stream_name: 'deschutes_river'
        })
      end

      spans = harvest_span_events!
      span = spans[1][1]

      assert_equal 'Kinesis/delete_stream/deschutes_river', span[0]['name']
      assert_equal 'aws_kinesis_data_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_describe_stream
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_stream({
          stream_name: 'deschutes_river',
          shard_count: 2
        })

        client.describe_stream({
          stream_name: 'deschutes_river'
        })
      end

      spans = harvest_span_events!
      span = spans[1][1]

      assert_equal 'Kinesis/describe_stream/deschutes_river', span[0]['name']
      assert_equal 'aws_kinesis_data_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_list_streams
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_stream({
          stream_name: 'deschutes_river',
          shard_count: 2
        })

        client.list_streams
      end

      spans = harvest_span_events!
      span = spans[1][1]

      assert_equal 'Kinesis/list_streams', span[2]['name']
      assert_equal 'aws_kinesis_data_streams', span[2]['cloud.platform']
      refute span[2]['cloud.resource_id']
    end
  end

  def test_add_tags_to_stream
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_stream({
          stream_name: 'deschutes_river',
          shard_count: 2
        })

        client.add_tags_to_stream({
          stream_name: 'deschutes_river',
          tags: {'TagKey' => 'salmon'}
        })
      end
      spans = harvest_span_events!
      span = spans[1][1]

      assert_equal 'Kinesis/add_tags_to_stream/deschutes_river', span[0]['name']
      assert_equal 'aws_kinesis_data_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_list_tags_for_stream
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_stream({
          stream_name: 'deschutes_river',
          shard_count: 2
        })

        client.add_tags_to_stream({
          stream_name: 'deschutes_river',
          tags: {'TagKey' => 'salmon'}
        })

        client.list_tags_for_stream({
          stream_name: 'deschutes_river'
        })
      end

      spans = harvest_span_events!
      span = spans[1][2]

      assert_equal 'Kinesis/list_tags_for_stream/deschutes_river', span[0]['name']
      assert_equal 'aws_kinesis_data_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_remove_tags_from_stream
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_stream({
          stream_name: 'deschutes_river',
          shard_count: 2
        })

        client.add_tags_to_stream({
          stream_name: 'deschutes_river',
          tags: {'TagKey' => 'salmon'}
        })

        client.remove_tags_from_stream({
          stream_name: 'deschutes_river',
          tag_keys: ['TagKey']
        })
      end

      spans = harvest_span_events!
      span = spans[1][2]

      assert_equal 'Kinesis/remove_tags_from_stream/deschutes_river', span[0]['name']
      assert_equal 'aws_kinesis_data_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_increase_stream_retention_period
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_stream({
          stream_name: 'deschutes_river',
          shard_count: 2
        })

        client.increase_stream_retention_period({
          stream_name: 'deschutes_river',
          retention_period_hours: 1
        })
      end

      spans = harvest_span_events!
      span = spans[1][1]

      assert_equal 'Kinesis/increase_stream_retention_period/deschutes_river', span[0]['name']
      assert_equal 'aws_kinesis_data_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_decrease_stream_retention_period
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_stream({
          stream_name: 'deschutes_river',
          shard_count: 2
        })

        client.decrease_stream_retention_period({
          stream_name: 'deschutes_river',
          retention_period_hours: 1
        })
      end

      spans = harvest_span_events!
      span = spans[1][1]

      assert_equal 'Kinesis/decrease_stream_retention_period/deschutes_river', span[0]['name']
      assert_equal 'aws_kinesis_data_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_put_record
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_stream({
          stream_name: 'deschutes_river',
          shard_count: 2
        })

        client.put_record({
          stream_name: 'deschutes_river',
          data: 'little lava lake',
          partition_key: 'wickiup'
        })
      end

      spans = harvest_span_events!
      span = spans[1][1]

      assert_equal 'Kinesis/put_record/deschutes_river', span[0]['name']
      assert_equal 'aws_kinesis_data_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_put_records
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_stream({
          stream_name: 'deschutes_river',
          shard_count: 2
        })

        client.put_records({
          stream_name: 'deschutes_river',
          records: [
            {
              data: 'spring chinook',
              explicit_hash_key: 'HashKey',
              partition_key: 'wickiup'
            },
            {
              data: 'summer steelhead',
              explicit_hash_key: 'HashKey',
              partition_key: 'wickiup'
            }
          ]
        })
      end

      spans = harvest_span_events!
      span = spans[1][1]

      assert_equal 'Kinesis/put_records/deschutes_river', span[2]['name']
      assert_equal 'aws_kinesis_data_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_get_record
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_stream({
          stream_name: 'deschutes_river',
          shard_count: 2
        })

        client.put_record({
          stream_name: 'deschutes_river',
          data: 'little lava lake',
          partition_key: 'wickiup'
        })

        client.get_records({
          shard_iterator: 'shard_iterator',
          stream_arn: 'arn:aws:kinesis:us-east-1:123456789012:stream/deschutes_river'
        })
      end

      spans = harvest_span_events!
      span = spans[1][2]

      assert_equal 'Kinesis/get_records', span[0]['name']
      assert_equal 'aws_kinesis_data_streams', span[2]['cloud.platform']
      assert_equal 'arn:aws:kinesis:us-east-1:123456789012:stream/deschutes_river', span[2]['cloud.resource_id']
    end
  end

  def test_update_shard_count
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_stream({
          stream_name: 'deschutes_river',
          shard_count: 2
        })

        client.update_shard_count({
          stream_name: 'deschutes_river',
          target_shard_count: 4,
          scaling_type: 'UNIFORM_SCALING'
        })
      end

      spans = harvest_span_events!
      span = spans[1][1]

      assert_equal 'Kinesis/update_shard_count/deschutes_river', span[0]['name']
      assert_equal 'aws_kinesis_data_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_split_shard
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_stream({
          stream_name: 'deschutes_river',
          shard_count: 2
        })

        client.split_shard({
          stream_name: 'deschutes_river',
          shard_to_split: 'shardId-000',
          new_starting_hash_key: 'HashKey'
        })
      end

      spans = harvest_span_events!
      span = spans[1][1]

      assert_equal 'Kinesis/split_shard/deschutes_river', span[0]['name']
      assert_equal 'aws_kinesis_data_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_merge_shards
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_stream({
          stream_name: 'deschutes_river',
          shard_count: 2
        })

        client.merge_shards({
          stream_name: 'deschutes_river',
          shard_to_merge: 'shardId-000',
          adjacent_shard_to_merge: 'shardId-001'
        })
      end

      spans = harvest_span_events!
      span = spans[1][1]

      assert_equal 'Kinesis/merge_shards/deschutes_river', span[0]['name']
      assert_equal 'aws_kinesis_data_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_get_shard_iterator
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_stream({
          stream_name: 'deschutes_river',
          shard_count: 2
        })

        client.get_shard_iterator({
          stream_name: 'deschutes_river',
          shard_id: 'shardId-000',
          shard_iterator_type: 'TRIM_HORIZON'
        })
      end

      spans = harvest_span_events!
      span = spans[1][1]

      assert_equal 'Kinesis/get_shard_iterator/deschutes_river', span[0]['name']
      assert_equal 'aws_kinesis_data_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_enable_enhanced_monitoring
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_stream({
          stream_name: 'deschutes_river',
          shard_count: 2
        })

        client.enable_enhanced_monitoring({
          stream_name: 'deschutes_river',
          shard_level_metrics: ['ALL']
        })
      end

      spans = harvest_span_events!
      span = spans[1][1]

      assert_equal 'Kinesis/enable_enhanced_monitoring/deschutes_river', span[0]['name']
      assert_equal 'aws_kinesis_data_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_disable_enhanced_monitoring
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_stream({
          stream_name: 'deschutes_river',
          shard_count: 2
        })

        client.disable_enhanced_monitoring({
          stream_name: 'deschutes_river',
          shard_level_metrics: ['ALL']
        })
      end

      spans = harvest_span_events!
      span = spans[1][1]

      assert_equal 'Kinesis/disable_enhanced_monitoring/deschutes_river', span[0]['name']
      assert_equal 'aws_kinesis_data_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_describe_limits
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        client.create_stream({
          stream_name: 'deschutes_river',
          shard_count: 2
        })

        client.describe_limits
      end

      spans = harvest_span_events!
      span = spans[1][1]

      assert_equal 'Kinesis/describe_limits', span[0]['name']
      assert_equal 'aws_kinesis_data_streams', span[2]['cloud.platform']
    end
  end
end
