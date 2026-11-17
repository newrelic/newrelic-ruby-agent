# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'

class AwsTest < Minitest::Test
  def test_create_arn
    service = 'test-service'
    region = 'us-test-region-1'
    account_id = '123456789'
    resource = 'test/test-resource'
    expected = 'arn:aws:test-service:us-test-region-1:123456789:test/test-resource'
    arn = NewRelic::Agent::Aws.create_arn(service, resource, region, account_id)

    assert_equal expected, arn
  end

  def test_create_arn_uses_region_partition
    arn = NewRelic::Agent::Aws.create_arn('lambda', 'function:my-func', 'us-gov-west-1', '123456789')

    assert_equal 'arn:aws-us-gov:lambda:us-gov-west-1:123456789:function:my-func', arn
  end

  def test_table_partition_from_region
    {
      'us-east-1' => 'aws',
      'cn-north-1' => 'aws-cn',
      'us-gov-west-1' => 'aws-us-gov',
      'us-iso-east-1' => 'aws-iso',
      'us-isob-east-1' => 'aws-iso-b',
      'eu-isoe-west-1' => 'aws-iso-e',
      'us-isof-south-1' => 'aws-iso-f',
      'eusc-de-east-1' => 'aws-eusc',
      'mars-north-1' => 'aws',
      '' => 'aws'
    }.each do |region, partition|
      assert_equal partition, NewRelic::Agent::Aws.table_partition_from_region(region), "region: #{region.inspect}"
    end
  end

  def test_partition_from_region_prefers_sdk
    NewRelic::Agent::Aws.stub(:sdk_partition_from_region, 'aws-sdk-says') do
      assert_equal 'aws-sdk-says', NewRelic::Agent::Aws.partition_from_region('us-east-1')
    end
  end

  def test_sdk_partition_from_region_uses_sdk_matcher
    matchers = Module.new do
      def self.aws_partition(_region)
        {'name' => 'aws-us-gov'}
      end
    end

    with_aws_endpoints_matchers(matchers) do
      assert_equal 'aws-us-gov', NewRelic::Agent::Aws.sdk_partition_from_region('us-gov-west-1')
    end
  end

  def test_sdk_partition_from_region_returns_nil_when_sdk_errors
    matchers = Module.new do
      def self.aws_partition(_region)
        raise 'kaboom'
      end
    end
    with_aws_endpoints_matchers(matchers) do
      assert_nil NewRelic::Agent::Aws.sdk_partition_from_region('us-gov-west-1')
      assert_equal 'aws-us-gov', NewRelic::Agent::Aws.partition_from_region('us-gov-west-1')
    end
  end

  def test_sdk_partition_from_region_returns_nil_when_sdk_returns_nothing
    matchers = Module.new do
      def self.aws_partition(_region)
        nil
      end
    end
    with_aws_endpoints_matchers(matchers) do
      assert_nil NewRelic::Agent::Aws.sdk_partition_from_region('cn-north-1')
      assert_equal 'aws-cn', NewRelic::Agent::Aws.partition_from_region('cn-north-1')
    end
  end

  def test_sdk_partition_from_region_returns_nil_for_empty_region
    matchers = Module.new do
      def self.aws_partition(_region)
        {'name' => 'aws-us-gov'}
      end
    end

    with_aws_endpoints_matchers(matchers) do
      assert_nil NewRelic::Agent::Aws.sdk_partition_from_region('')
    end
  end

  def test_get_account_id_decodes_access_key
    config = mock
    mock_credentials = mock
    mock_credentials.stubs(:credentials).returns(mock_credentials)
    mock_credentials.stubs(:access_key_id).returns('AKIAIOSFODNN7EXAMPLE') # this is a fake access key id from aws docs
    config.stubs(:credentials).returns(mock_credentials)

    account_id = NewRelic::Agent::Aws.get_account_id(config)

    assert_equal 36315003739, account_id
  end

  def test_get_account_id_uses_config
    config = mock

    with_config(:'cloud.aws.account_id' => '123456789') do
      assert_equal '123456789', NewRelic::Agent::Aws.get_account_id(config)
    end
  end

  private

  def with_aws_endpoints_matchers(matchers)
    aws = Module.new
    endpoints = Module.new
    endpoints.const_set(:Matchers, matchers)
    aws.const_set(:Endpoints, endpoints)
    Object.const_set(:Aws, aws)
    begin
      yield
    ensure
      Object.send(:remove_const, :Aws)
    end
  end
end
