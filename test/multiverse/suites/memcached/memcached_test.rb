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

    def test_handles_cas
      expected_metrics = ["cas"]
      expected_metrics = ["single_get", "single_cas"] if @cache.class.name == 'Memcached' && Memcached::VERSION >= '1.8.0'
      expected_metrics = ["Memcache/allOther"] + expected_metrics.map {|m| ["Memcache/#{m}", "Memcache/#{m}:OtherTransaction/Background/#{self.class}/bg_task"] }.flatten

      @engine.clear_stats

      perform_action_with_newrelic_trace(:name => 'bg_task', :category => :task) do
        @cache.cas(@key) {|val| val += 2}
      end

      compare_metrics expected_metrics, @engine.metrics.select{|m| m =~ /^memcache.*/i}
      assert_equal 3, @cache.get(@key)
    end
  end
end