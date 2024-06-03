# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'

class AwsTest < Minitest::Test
  def test_create_arn
    config = mock
    config.stubs(:region).returns('us-test-region-1')
    mock_credentials = mock
    mock_credentials.stubs(:credentials).returns(mock_credentials)
    mock_credentials.stubs(:access_key_id).returns('AKIAIOSFODNN7EXAMPLE') # this is a fake access key id from aws docs
    config.stubs(:credentials).returns(mock_credentials)

    service = 'test-service'
    resource = 'test/test-resource'
    arn = NewRelic::Agent::Aws.create_arn(service, resource, config)

    expected = 'arn:aws:test-service:us-test-region-1:36315003739:test/test-resource'

    assert_equal expected, arn
  end
end
