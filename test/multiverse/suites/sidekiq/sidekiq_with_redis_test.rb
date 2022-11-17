# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'bundler/inline'

class SidekiqWithRedisTest < MiniTest::Test
  #
  # Regression test for
  #   https://github.com/newrelic/newrelic-ruby-agent/issues/1639
  #
  # PR 1611 introduced a new `call_pipelined_with_tracing` method to
  # `lib/new_relic/agent/instrumentation/redis/instrumentation.rb`. That method
  # is defined on all instrumented instances of RedisClient (defined by the
  # `redis-client` gem) when v5.0+ of the `redis` gem (which requires
  # `redis-client`) is used. Originally the new method performed a
  # `client.db` call on `self` to get at the client's configured database value.
  # At the time, `client` was assumed to always return an instance of
  # `Redis::Client` which is a class defined by the `redis` gem. This
  # `Redis::Client` class has a `db` helper method that exposes the configured
  # database value.
  #
  # With Issue 1639 it was discovered that `client` could return an instance
  # of `RedisClient` (defined by the `redis-client` gem) instead of
  # `Redis::Client` (defined by the `redis` gem). The original `client.db` call
  # was updated to read `client.config.db` instead. This approach is known to
  # work for instances of `RedisClient` and `Redis::Client`, as
  # `Redis::Client#db` is just a helper method that calls `config.db`.
  #
  # This test reproduces the problem by placing an instance of `RedisClient` in
  # scope when the `call_pipelined_with_tracing` method calls `client`, and
  # confirms that the instrumentation no longer (and never again) errors out.
  #
  # NOTE: Because Sidekiq v7.0+ can use `redis-client` without `redis`, this
  #       test brings in the `redis` gem directly via `bundler/inline`
  def test_redis_client_pipelined_calls_work
    skip unless run_these_tests?

    gemfile do
      source 'https://rubygems.org'

      gem 'redis'
    end

    require 'sidekiq'
    require 'newrelic_rpm'

    conn = Sidekiq::RedisConnection.create
    key = 'pineapple'
    value = 'carrot'
    result = nil

    conn.with do |c|
      c._client.pipelined do |p|
        p.call_v([:set, key, value])
      end
      result = c._client.call(:get, key)
    end

    assert_equal value, result
  end

  private

  def run_these_tests?
    # these tests aren't impacted by Ruby version
    return false unless RUBY_VERSION >= '3.1.2'

    # only test with environments that have not already bundled the redis gem
    !Gem::Specification.all.any? { |s| s.name == 'redis' }
  end
end
