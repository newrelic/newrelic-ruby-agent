# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require "./memcache_test_cases"

if defined?(MemCache)
  class MemcacheTest < Minitest::Test
    include MemcacheTestCases

    def setup
      @cache = MemCache.new("localhost:11211")
    end

    if MemCache::VERSION <= "1.5.0"
      undef_method :test_append_in_web, :test_prepend_in_web, :test_replace_in_web,
                   :test_append_in_background, :test_prepend_in_background,
                   :test_replace_in_background
    end

    if MemCache::VERSION <= "1.7.0"
      undef_method :test_cas_in_web, :test_cas_in_background
    end

    def simulate_error
      MemCache.any_instance.stubs("with_server").raises(simulated_error_class, "No server available")
      MemCache.any_instance.stubs("request_setup").raises(simulated_error_class, "No server available")
      key = set_key_for_testcase
      @cache.get(key)
    end

    def simulated_error_class
      MemCache::MemCacheError
    end

  end
end