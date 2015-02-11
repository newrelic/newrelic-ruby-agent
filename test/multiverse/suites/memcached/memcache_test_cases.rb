# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module MemcacheTestCases
  include NewRelic::Agent::Instrumentation::ControllerInstrumentation

  def after_setup
    NewRelic::Agent.manual_start
    @engine = NewRelic::Agent.instance.stats_engine

    @key = randomized_key
    @cache.set(@key, 1)
  end

  def teardown
    @cache.delete(@key) rescue nil
  end

  def randomized_key
    "test_#{rand(1e18)}"
  end

  def _call_test_method_in_web_transaction(method, *args)
    @engine.clear_stats
    perform_action_with_newrelic_trace(:name=>'action', :category => :controller) do
      @cache.send(method.to_sym, *[@key, *args])
    end
  end

  def _call_test_method_in_background_task(method, *args)
    @engine.clear_stats
    perform_action_with_newrelic_trace(:name => 'bg_task', :category => :task) do
      @cache.send(method.to_sym, *[@key, *args])
    end
  end

  def test_reads_web
    commands = ['get']
    commands << 'get_multi'
    expected_metrics = commands
    expected_metrics = ['single_get', 'multi_get'] if @cache.class.name == 'Memcached' && Memcached::VERSION >= '1.8.0'
    commands.zip(expected_metrics) do |method, metric|
      if @cache.class.method_defined?(method)
        _call_test_method_in_web_transaction(method)
        compare_metrics ["Memcache/#{metric}", "Memcache/allWeb", "Memcache/#{metric}:Controller/#{self.class}/action"],
        @engine.metrics.select{|m| m =~ /^memcache.*/i}
      end
    end
  end

  def test_writes_web
    %w[delete].each do |method|
      if @cache.class.method_defined?(method)
        _call_test_method_in_web_transaction(method)
        expected_metrics = ["Memcache/#{method}", "Memcache/allWeb", "Memcache/#{method}:Controller/#{self.class}/action"]
        compare_metrics expected_metrics, @engine.metrics.select{|m| m =~ /^memcache.*/i}
      end
    end

    %w[set add].each do |method|
      @cache.delete(@key) rescue nil
      if @cache.class.method_defined?(method)
        expected_metrics = ["Memcache/#{method}", "Memcache/allWeb", "Memcache/#{method}:Controller/#{self.class}/action"]
        _call_test_method_in_web_transaction(method, 'value')
        compare_metrics expected_metrics, @engine.metrics.select{|m| m =~ /^memcache.*/i}
      end
    end
  end

  def test_reads_background
    commands = ['get']
    commands << 'get_multi'
    expected_metrics = commands
    expected_metrics = ['single_get', 'multi_get'] if @cache.class.name == 'Memcached' && Memcached::VERSION >= '1.8.0'
    commands.zip(expected_metrics) do |method, metric|
      if @cache.class.method_defined?(method)
        _call_test_method_in_background_task(method)
        compare_metrics ["Memcache/#{metric}", "Memcache/allOther", "Memcache/#{metric}:OtherTransaction/Background/#{self.class}/bg_task"],
        @engine.metrics.select{|m| m =~ /^memcache.*/i}
      end
    end
  end

  def test_writes_background
    %w[delete].each do |method|
      expected_metrics = ["Memcache/#{method}", "Memcache/allOther", "Memcache/#{method}:OtherTransaction/Background/#{self.class}/bg_task"]
      if @cache.class.method_defined?(method)
        _call_test_method_in_background_task(method)
        compare_metrics expected_metrics, @engine.metrics.select{|m| m =~ /^memcache.*/i}
      end
    end

    %w[set add].each do |method|
      @cache.delete(@key) rescue nil
      expected_metrics = ["Memcache/#{method}", "Memcache/allOther", "Memcache/#{method}:OtherTransaction/Background/#{self.class}/bg_task"]
      if @cache.class.method_defined?(method)
        _call_test_method_in_background_task(method, 'value')
        compare_metrics expected_metrics, @engine.metrics.select{|m| m =~ /^memcache.*/i}
      end
    end
  end
end
