# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "./memcache_test_cases"

if defined?(MemCache)
  class MemcacheTest < Minitest::Test
    include MemcacheTestCases

    def setup
      @cache = MemCache.new("localhost:11211")
    end
  end
end