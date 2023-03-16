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
    skip 'The CI fails when trying to run this test because of a Bundler error' if RUBY_VERSION.match?(/^3\.1/)
    skip 'Testing conducted only using Sidekiq v7.0+ with redis not yet bundled' unless sidekiq_without_redis?

    gemfile do
      source 'https://rubygems.org'

      gem 'redis'
    end

    require 'newrelic_rpm'

    conn = Sidekiq::RedisConnection.create
    key = 'pineapple'
    value = 'carrot'
    result = nil

    conn.with do |c|
      client = c.instance_variable_get(:@client)
      client.pipelined do |p|
        p.call_v([:set, key, value])
      end
      result = client.call(:get, key)
    end

    assert_equal value, result
  end

  private

  # Sidekiq v7.0 depends on the redis-client gem and by default will not have
  # the redis gem present. Issue #1639 arose from having both Sidekiq v7.0 and
  # the redis gem. For this testing, we want to identify an environment that
  # has Sidekiq v7.0 but does not have the redis gem present. We will then
  # introduce the redis gem to the environment and ensure that things still
  # work as expected.
  def sidekiq_without_redis?
    require 'sidekiq'
    return false unless Gem::Version.new(Sidekiq::VERSION) >= Gem::Version.new('7.0.0')
    return false if defined?(RedisClient).nil?

    # NOTE: introspection through Bundler/RubyGems methods produces warnings,
    #       so we just use a begin/rescue to test for the presence of redis
    begin
      require 'redis'
      false # redis is already bundled - do not test
    rescue LoadError
      true # redis is not yet bundled, proceed to test
    end
  end
end
