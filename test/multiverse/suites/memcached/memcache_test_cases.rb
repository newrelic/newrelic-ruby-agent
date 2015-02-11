# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module MemcacheTestCases
  def after_setup
    @keys = []
  end

  def teardown
    @keys.each { |key| @cache.delete(key) rescue nil }
    NewRelic::Agent.drop_buffered_data
  end

  def randomized_key
    "test_#{rand(1e18)}".tap do |key|
      @keys << key
    end
  end

  def set_key_for_testcase(value = "value")
    randomized_key.tap do |key|
      @cache.set(key, value)
      NewRelic::Agent.drop_buffered_data
    end
  end

  def expected_web_metrics(command)
    [
      "Memcache/#{command}",
      "Memcache/allWeb",
      ["Memcache/#{command}", "Controller/#{self.class}/action"]
    ]
  end

  def expected_bg_metrics(command)
    [
      "Memcache/#{command}",
      "Memcache/allOther",
      ["Memcache/#{command}", "OtherTransaction/Background/#{self.class}/bg_task"]
    ]
  end

  def test_get_in_web
    key = set_key_for_testcase

    expected_metrics = expected_web_metrics(:get)

    in_web_transaction("Controller/#{self.class}/action") do
      @cache.get(key)
    end

    assert_metrics_recorded_exclusive expected_metrics, :filter => /^memcache.*/i
  end

  def test_get_multi_in_web
    key = set_key_for_testcase

    expected_metrics = expected_web_metrics(:get_multi)

    in_web_transaction("Controller/#{self.class}/action") do
      @cache.get_multi(key)
    end

    assert_metrics_recorded_exclusive expected_metrics, :filter => /^memcache.*/i
  end

  def test_set_in_web
    expected_metrics = expected_web_metrics(:set)

    in_web_transaction("Controller/#{self.class}/action") do
      @cache.set(randomized_key, "value")
    end

    assert_metrics_recorded_exclusive expected_metrics, :filter => /^memcache.*/i
  end

  def test_add_in_web
    expected_metrics = expected_web_metrics(:add)

    in_web_transaction("Controller/#{self.class}/action") do
      @cache.add(randomized_key, "value")
    end

    assert_metrics_recorded_exclusive expected_metrics, :filter => /^memcache.*/i
  end

  def test_delete_in_web
    key = set_key_for_testcase

    expected_metrics = expected_web_metrics(:delete)

    in_web_transaction("Controller/#{self.class}/action") do
      @cache.delete(key)
    end

    assert_metrics_recorded_exclusive expected_metrics, :filter => /^memcache.*/i
  end

  def test_get_in_background
    key = set_key_for_testcase

    expected_metrics = expected_bg_metrics(:get)

    in_background_transaction("OtherTransaction/Background/#{self.class}/bg_task") do
      @cache.get(key)
    end

    assert_metrics_recorded_exclusive expected_metrics, :filter => /^memcache.*/i
  end

  def test_get_multi_in_background
    key = set_key_for_testcase

    expected_metrics = expected_bg_metrics(:get_multi)

    in_background_transaction("OtherTransaction/Background/#{self.class}/bg_task") do
      @cache.get_multi(key)
    end

    assert_metrics_recorded_exclusive expected_metrics, :filter => /^memcache.*/i
  end

  def test_set_in_background
    expected_metrics = expected_bg_metrics(:set)

    in_background_transaction("OtherTransaction/Background/#{self.class}/bg_task") do
      @cache.set(randomized_key, "value")
    end

    assert_metrics_recorded_exclusive expected_metrics, :filter => /^memcache.*/i
  end

  def test_add_in_background
    expected_metrics = expected_bg_metrics(:add)

    in_background_transaction("OtherTransaction/Background/#{self.class}/bg_task") do
      @cache.add(randomized_key, "value")
    end

    assert_metrics_recorded_exclusive expected_metrics, :filter => /^memcache.*/i
  end

  def test_delete_in_background
    key = set_key_for_testcase

    expected_metrics = expected_bg_metrics(:delete)

    in_background_transaction("OtherTransaction/Background/#{self.class}/bg_task") do
      @cache.delete(key)
    end

    assert_metrics_recorded_exclusive expected_metrics, :filter => /^memcache.*/i
  end
end
