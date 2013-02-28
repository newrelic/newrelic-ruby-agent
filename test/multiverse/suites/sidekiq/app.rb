# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "newrelic_rpm"

REDIS_PORT = ENV['NEWRELIC_MULTIVERSE_REDIS_PORT']
REDIS_URL  = "redis://localhost:#{REDIS_PORT}/0"

Sidekiq.configure_server do |config|
  config.redis = { :url => REDIS_URL }
end

Sidekiq.configure_client do |config|
  config.redis = { :url => REDIS_URL }
end

$redis = Redis.new(:port => REDIS_PORT)

class TestWorker
  include Sidekiq::Worker
  def perform(key, val)
    $redis.sadd(key, val)
  end
end
