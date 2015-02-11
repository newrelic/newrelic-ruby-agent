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

  def commands
    ['get', 'get_multi']
  end

  def test_reads_web
    commands.each do |command|
      if @cache.class.method_defined?(command)
        _call_test_method_in_web_transaction(command)

        expected_metrics = [
          "Memcache/#{command}",
          "Memcache/allWeb",
          ["Memcache/#{command}", "Controller/#{self.class}/action"]
        ]

        assert_metrics_recorded_exclusive expected_metrics, :filter => /^memcache.*/i
      end
    end
  end

  def test_writes_web
    %w[delete].each do |method|
      if @cache.class.method_defined?(method)
        _call_test_method_in_web_transaction(method)

        expected_metrics = [
          "Memcache/#{method}",
          "Memcache/allWeb",
          ["Memcache/#{method}", "Controller/#{self.class}/action"]
        ]

        assert_metrics_recorded_exclusive expected_metrics, :filter => /^memcache.*/i
      end
    end

    %w[set add].each do |method|
      @cache.delete(@key) rescue nil
      if @cache.class.method_defined?(method)

        expected_metrics = [
          "Memcache/#{method}",
          "Memcache/allWeb",
          ["Memcache/#{method}", "Controller/#{self.class}/action"]
        ]

        _call_test_method_in_web_transaction(method, 'value')
        assert_metrics_recorded_exclusive expected_metrics, :filter => /^memcache.*/i
      end
    end
  end

  def test_reads_background
    commands.each do |command|
      if @cache.class.method_defined?(command)
        _call_test_method_in_background_task(command)

        expected_metrics = [
          "Memcache/#{command}",
          "Memcache/allOther",
          ["Memcache/#{command}", "OtherTransaction/Background/#{self.class}/bg_task"]
        ]

        assert_metrics_recorded_exclusive expected_metrics, :filter => /^memcache.*/i
      end
    end
  end

  def test_writes_background
    %w[delete].each do |method|

      expected_metrics = [
        "Memcache/#{method}",
        "Memcache/allOther",
        ["Memcache/#{method}", "OtherTransaction/Background/#{self.class}/bg_task"]
      ]

      if @cache.class.method_defined?(method)
        _call_test_method_in_background_task(method)
        assert_metrics_recorded_exclusive expected_metrics, :filter => /^memcache.*/i
      end
    end

    %w[set add].each do |method|
      @cache.delete(@key) rescue nil

      expected_metrics = [
        "Memcache/#{method}",
        "Memcache/allOther",
        ["Memcache/#{method}", "OtherTransaction/Background/#{self.class}/bg_task"]
      ]

      if @cache.class.method_defined?(method)
        _call_test_method_in_background_task(method, 'value')
        assert_metrics_recorded_exclusive expected_metrics, :filter => /^memcache.*/i
      end
    end
  end
end
