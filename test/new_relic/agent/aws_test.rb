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

    with_config(aws_account_id: account_id) do
      arn = NewRelic::Agent::Aws.create_arn(service, resource, region)

      assert_equal expected, arn
    end
  end

  def test_doesnt_create_arn_no_account_id
    assert_nil NewRelic::Agent::Aws.create_arn('service', 'resource', 'region')
  end
end
