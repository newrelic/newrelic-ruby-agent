# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'redis'
require 'newrelic_rpm'

if !NewRelic::Agent::Datastores::Redis.is_supported_version?
  class NewRelic::Agent::Instrumentation::RedisUnsupportedVersionTest < Minitest::Test
    def setup
      @redis = Redis.new
    end

    def test_no_metrics_recorded_for_get
      @redis.get('hello')

      assert_no_metrics_match(/redis/i)
    end
  end
end
