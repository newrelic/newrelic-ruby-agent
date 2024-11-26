# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class FirehoseInstrumentationTest < Minitest::Test
  def setup
    Aws.config.update(stub_responses: true)
  end

  def teardown
    NewRelic::Agent.instance.stats_engine.clear_stats
  end

  def create_client
    Aws::Firehose::Client.new(region: 'us-east-2')
  end

  def test_all_attributes_added_to_segment_in_create_delivery_stream
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_delivery_stream({
          delivery_stream_name: 'the_shire'
        })
      end

      spans = harvest_span_events!
      span = spans[1][0]

      assert_equal 'Firehose/create_delivery_stream/the_shire', span[0]['name']
      assert_equal 'aws_kinesis_delivery_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_delete_delivery_stream
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_delivery_stream({
          delivery_stream_name: 'the_shire'
        })

        client.delete_delivery_stream({
          delivery_stream_name: 'the_shire'
        })
      end

      spans = harvest_span_events!
      span = spans[1][1]

      assert_equal 'Firehose/delete_delivery_stream/the_shire', span[0]['name']
      assert_equal 'aws_kinesis_delivery_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_describe_delivery_stream
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_delivery_stream({
          delivery_stream_name: 'the_shire'
        })

        client.describe_delivery_stream({
          delivery_stream_name: 'the_shire'
        })
      end

      spans = harvest_span_events!
      span = spans[1][1]

      assert_equal 'Firehose/describe_delivery_stream/the_shire', span[0]['name']
      assert_equal 'aws_kinesis_delivery_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_list_delivery_streams
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_delivery_stream({
          delivery_stream_name: 'the_shire'
        })

        client.list_delivery_streams
      end

      spans = harvest_span_events!
      span = spans[1][1]

      assert_equal 'Firehose/list_delivery_streams', span[2]['name']
      assert_equal 'aws_kinesis_delivery_streams', span[2]['cloud.platform']
      refute span[2]['cloud.resource_id']
    end
  end

  def test_tag_delivery_stream
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_delivery_stream({
          delivery_stream_name: 'the_shire'
        })

        client.tag_delivery_stream({
          delivery_stream_name: 'the_shire',
          tags: [{key: 'TagKey', value: 'salmon'}]
        })
      end
      spans = harvest_span_events!
      span = spans[1][1]

      assert_equal 'Firehose/tag_delivery_stream/the_shire', span[0]['name']
      assert_equal 'aws_kinesis_delivery_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_list_tags_for_delivery_stream
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_delivery_stream({
          delivery_stream_name: 'the_shire'
        })

        client.tag_delivery_stream({
          delivery_stream_name: 'the_shire',
          tags: [{key: 'hobbit', value: 'frodo_baggins'}]
        })

        client.list_tags_for_delivery_stream({
          delivery_stream_name: 'the_shire'
        })
      end

      spans = harvest_span_events!
      span = spans[1][2]

      assert_equal 'Firehose/list_tags_for_delivery_stream/the_shire', span[0]['name']
      assert_equal 'aws_kinesis_delivery_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_untag_delivery_stream
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_delivery_stream({
          delivery_stream_name: 'the_shire'
        })

        client.tag_delivery_stream({
          delivery_stream_name: 'the_shire',
          tags: [{key: 'hobbit', value: 'frodo_baggins'}]
        })

        client.untag_delivery_stream({
          delivery_stream_name: 'the_shire',
          tag_keys: ['hobbit']
        })
      end

      spans = harvest_span_events!
      span = spans[1][2]

      assert_equal 'Firehose/untag_delivery_stream/the_shire', span[0]['name']
      assert_equal 'aws_kinesis_delivery_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_put_record
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_delivery_stream({
          delivery_stream_name: 'the_shire'
        })

        client.put_record({
          delivery_stream_name: 'the_shire',
          record: {data: 'samwise gamgee'}
        })
      end

      spans = harvest_span_events!
      span = spans[1][1]

      assert_equal 'Firehose/put_record/the_shire', span[0]['name']
      assert_equal 'aws_kinesis_delivery_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_put_record_batch
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_delivery_stream({
          delivery_stream_name: 'the_shire'
        })

        client.put_record_batch({
          delivery_stream_name: 'the_shire',
          records: [
            {
              data: 'legolas'
            },
            {
              data: 'gimli'
            }
          ]
        })
      end

      spans = harvest_span_events!
      span = spans[1][1]

      assert_equal 'Firehose/put_record_batch/the_shire', span[2]['name']
      assert_equal 'aws_kinesis_delivery_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_start_delivery_stream_encryption
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_delivery_stream({
          delivery_stream_name: 'the_shire'
        })

        client.start_delivery_stream_encryption({
          delivery_stream_name: 'the_shire'
        })
      end

      spans = harvest_span_events!
      span = spans[1][1]

      assert_equal 'Firehose/start_delivery_stream_encryption/the_shire', span[0]['name']
      assert_equal 'aws_kinesis_delivery_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_stop_delivery_stream_encryption
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_delivery_stream({
          delivery_stream_name: 'the_shire'
        })

        client.stop_delivery_stream_encryption({
          delivery_stream_name: 'the_shire'
        })
      end

      spans = harvest_span_events!
      span = spans[1][1]

      assert_equal 'Firehose/stop_delivery_stream_encryption/the_shire', span[0]['name']
      assert_equal 'aws_kinesis_delivery_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end

  def test_update_destination
    client = create_client

    NewRelic::Agent::Aws.stub(:create_arn, 'test-arn') do
      in_transaction do |txn|
        txn.stubs(:sampled?).returns(true)
        client.create_delivery_stream({
          delivery_stream_name: 'the_shire'
        })

        client.update_destination({
          delivery_stream_name: 'the_shire',
          current_delivery_stream_version_id: '1',
          destination_id: '2',
          s3_destination_update: {
            bucket_arn: 'arn:aws:s3:::my-bucket',
            role_arn: 'arn:aws:iam::123456789012:role/firehose_delivery_role'
          }
        })
      end

      spans = harvest_span_events!
      span = spans[1][1]

      assert_equal 'Firehose/update_destination/the_shire', span[0]['name']
      assert_equal 'aws_kinesis_delivery_streams', span[2]['cloud.platform']
      assert_equal 'test-arn', span[2]['cloud.resource_id']
    end
  end
end
