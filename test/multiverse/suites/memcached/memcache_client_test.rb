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

    def test_append_in_web
      super if MemCache::VERSION > "1.5.0"
    end

    def test_prepend_in_web
      super if MemCache::VERSION > "1.5.0"
    end

    def test_replace_in_web
      super if MemCache::VERSION > "1.5.0"
    end

    def test_append_in_background
      super if MemCache::VERSION > "1.5.0"
    end

    def test_prepend_in_background
      super if MemCache::VERSION > "1.5.0"
    end

    def test_replace_in_background
      super if MemCache::VERSION > "1.5.0"
    end

    def test_cas_in_web
      super if MemCache::VERSION > "1.7.0"
    end

    def test_cas_in_background
      super if MemCache::VERSION > "1.7.0"
    end
  end
end