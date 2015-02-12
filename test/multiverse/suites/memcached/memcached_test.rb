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

        assert_metrics_recorded_exclusive expected_metrics, :filter => /^memcache.*/i
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

      assert_metrics_recorded_exclusive expected_metrics, :filter => /^memcache.*/i

    end

    def test_get_in_background
      if Memcached::VERSION >= '1.8.0'
        key = set_key_for_testcase

        expected_metrics = expected_bg_metrics(:single_get)

        in_background_transaction("OtherTransaction/Background/#{self.class}/bg_task") do
          @cache.get(key)
        end

        assert_metrics_recorded_exclusive expected_metrics, :filter => /^memcache.*/i
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

      assert_metrics_recorded_exclusive expected_metrics, :filter => /^memcache.*/i
    end

    def test_handles_cas
      key = set_key_for_testcase(1)
      methods = ["cas"]
      methods = ["single_get", "single_cas"] if Memcached::VERSION >= '1.8.0'
      expected_metrics = ["Memcache/allOther"]

      methods.map do |m|
        expected_metrics << "Memcache/#{m}"
        expected_metrics << ["Memcache/#{m}", "OtherTransaction/Background/#{self.class}/bg_task"]
      end

      in_background_transaction("OtherTransaction/Background/#{self.class}/bg_task") do
        @cache.cas(key) {|val| val += 2}
      end

      assert_metrics_recorded_exclusive expected_metrics, :filter => /^memcache.*/i
      assert_equal 3, @cache.get(key)
    end
  end
end