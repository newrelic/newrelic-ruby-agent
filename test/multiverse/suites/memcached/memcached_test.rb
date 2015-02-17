# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "./memcache_test_cases"

if defined?(Memcached)
  class MemcachedTest < Minitest::Test
    include MemcacheTestCases

    def setup
      @cache = Memcached.new('localhost', :support_cas => true)
    end

    def test_get_in_web
      if Memcached::VERSION >= '1.8.0'
        key = set_key_for_testcase

        expected_metrics = expected_web_metrics(:single_get)

        in_web_transaction("Controller/#{self.class}/action") do
          @cache.get(key)
        end

        assert_memcache_metrics_recorded expected_metrics
      else
        super
      end
    end

    def test_get_multi_in_web
      return unless Memcached::VERSION >= '1.8.0'
      key = set_key_for_testcase

      expected_metrics = expected_web_metrics(:multi_get)

      in_web_transaction("Controller/#{self.class}/action") do
        @cache.get([key])
      end

      assert_memcache_metrics_recorded expected_metrics
    end

    def test_incr_in_web
      # the memcached gem will raise NotFound error if calling incr on a nonexistent key
      # this overrides the test in the shared memcache_test_cases file
      key = set_key_for_testcase(1)
      expected_metrics = expected_web_metrics(:incr)

      in_web_transaction("Controller/#{self.class}/action") do
        @cache.incr(key, 1)
      end

      assert_memcache_metrics_recorded expected_metrics
    end

    def test_decr_in_web
      # the memcached gem will raise NotFound error if calling incr on a nonexistent key
      # this overrides the test in the shared memcache_test_cases file
      key = set_key_for_testcase(1)
      expected_metrics = expected_web_metrics(:decr)

      in_web_transaction("Controller/#{self.class}/action") do
        @cache.decr(key, 1)
      end

      assert_memcache_metrics_recorded expected_metrics
    end

    def test_cas_in_web
      key = set_key_for_testcase(1)

      if Memcached::VERSION >= '1.8.0'
        expected_metrics = (expected_web_metrics(:single_get) + expected_web_metrics(:single_cas)).uniq
      else
        expected_metrics = expected_web_metrics(:cas)
      end

      in_web_transaction("Controller/#{self.class}/action") do
        @cache.cas(key) {|val| val += 2}
      end

      assert_memcache_metrics_recorded expected_metrics
      assert_equal 3, @cache.get(key)
    end

    def test_get_in_background
      if Memcached::VERSION >= '1.8.0'
        key = set_key_for_testcase

        expected_metrics = expected_bg_metrics(:single_get)

        in_background_transaction("OtherTransaction/Background/#{self.class}/bg_task") do
          @cache.get(key)
        end

        assert_memcache_metrics_recorded expected_metrics
      else
        super
      end
    end

    def test_get_multi_in_background
      return unless Memcached::VERSION >= '1.8.0'

      key = set_key_for_testcase

      expected_metrics = expected_bg_metrics(:multi_get)

      in_background_transaction("OtherTransaction/Background/#{self.class}/bg_task") do
        @cache.get([key])
      end

      assert_memcache_metrics_recorded expected_metrics
    end

    def test_incr_in_background
      # the memcached gem will raise NotFound error if calling incr on a nonexistent key
      # this overrides the test in the shared memcache_test_cases file
      key = set_key_for_testcase(1)
      expected_metrics = expected_bg_metrics(:incr)

      in_background_transaction("OtherTransaction/Background/#{self.class}/bg_task") do
        @cache.incr(key, 1)
      end

      assert_memcache_metrics_recorded expected_metrics
    end

    def test_decr_in_background
      # the memcached gem will raise NotFound error if calling decr on a nonexistent key
      # this overrides the test in the shared memcache_test_cases file
      key = set_key_for_testcase(1)
      expected_metrics = expected_bg_metrics(:decr)

      in_background_transaction("OtherTransaction/Background/#{self.class}/bg_task") do
        @cache.decr(key, 1)
      end

      assert_memcache_metrics_recorded expected_metrics
    end

    def test_cas_in_background
      key = set_key_for_testcase(1)
      if Memcached::VERSION >= '1.8.0'
        expected_metrics = (expected_bg_metrics(:single_get) + expected_bg_metrics(:single_cas)).uniq
      else
        expected_metrics = expected_bg_metrics(:cas)
      end

      in_background_transaction("OtherTransaction/Background/#{self.class}/bg_task") do
        @cache.cas(key) {|val| val += 2}
      end

      assert_memcache_metrics_recorded expected_metrics
      assert_equal 3, @cache.get(key)
    end
  end
end