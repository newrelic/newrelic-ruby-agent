# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "./memcache_test_cases"

if defined?(Dalli)
  class DalliTest < Minitest::Test
    include MemcacheTestCases

    def setup
      @cache = Dalli::Client.new("127.0.0.1:11211", :socket_timeout => 2.0)
    end
  end

  if Dalli::VERSION >= '2.7'
    require 'dalli/cas/client'
    DependencyDetection.detect!

    class DalliCasClientTest < DalliTest

      def after_setup
        super
        @cas_key = set_key_for_testcase(1)
      end

      def test_get_cas
        expected_metrics = expected_web_metrics(:get_cas)

        value = nil
        in_web_transaction("Controller/#{self.class}/action") do
          value, _ = @cache.get_cas(@cas_key)
        end

        assert_memcache_metrics_recorded expected_metrics
        assert_equal value, @cache.get(@cas_key)
      end

      def test_get_multi_cas
        expected_metrics = expected_web_metrics(:get_multi_cas)

        value = nil
        in_web_transaction("Controller/#{self.class}/action") do
          # returns { "cas_key" => [value, cas] }
          value, _ = @cache.get_multi_cas(@cas_key)
        end

        assert_memcache_metrics_recorded expected_metrics
        assert_equal 1, value.values.length
        assert_equal value.values.first.first, @cache.get(@cas_key)
      end


      def test_set_cas
        expected_metrics = expected_web_metrics(:set_cas)

        in_web_transaction("Controller/#{self.class}/action") do
          @cache.set_cas(@cas_key, 2, 0)
        end

        assert_memcache_metrics_recorded expected_metrics
        assert_equal 2, @cache.get(@cas_key)
      end

      def test_replace_cas
        expected_metrics = expected_web_metrics(:replace_cas)

        in_web_transaction("Controller/#{self.class}/action") do
          @cache.replace_cas(@cas_key, 2, 0)
        end

        assert_memcache_metrics_recorded expected_metrics
        assert_equal 2, @cache.get(@cas_key)
      end

      def test_delete_cas
        expected_metrics = expected_web_metrics(:delete_cas)

        in_web_transaction("Controller/#{self.class}/action") do
          @cache.delete_cas(@cas_key)
        end

        assert_memcache_metrics_recorded expected_metrics
        assert_equal nil, @cache.get(@cas_key)
      end

    end
  end
end
