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
end
