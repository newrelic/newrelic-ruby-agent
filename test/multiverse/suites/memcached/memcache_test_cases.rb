# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

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
      "Datastore/all",
      "Datastore/Memcached/all",
      "Datastore/operation/Memcached/#{command}",
      "Datastore/allWeb",
      "Datastore/Memcached/allWeb",
      ["Datastore/operation/Memcached/#{command}", "Controller/#{self.class}/action"]
    ]
  end

  def expected_bg_metrics(command)
    [
      "Datastore/all",
      "Datastore/Memcached/all",
      "Datastore/operation/Memcached/#{command}",
      "Datastore/allOther",
      "Datastore/Memcached/allOther",
      ["Datastore/operation/Memcached/#{command}", "OtherTransaction/Background/#{self.class}/bg_task"]
    ]
  end

  def assert_memcache_metrics_recorded(expected_metrics)
    assert_metrics_recorded_exclusive expected_metrics, :filter => /^datastore.*/i
  end

  def test_noticed_error_at_segment_and_txn_on_error
    txn = nil
    begin
      in_web_transaction("Controller/#{self.class}/action") do |web_txn|
        txn = web_txn
        simulate_error
      end
    rescue StandardError => e
      # NOP -- allowing span and transaction to notice error
    end
    assert_segment_noticed_error txn, /Memcached\/set$/, simulated_error_class.name, /No server available/i
    assert_transaction_noticed_error txn, simulated_error_class.name
  end

  def test_noticed_error_only_at_segment_on_error
    txn = nil
    in_web_transaction("Controller/#{self.class}/action") do |web_txn|
      begin
        txn = web_txn
        simulate_error
      rescue StandardError => e
        # NOP -- allowing ONLY span to notice error
      end
    end

    assert_segment_noticed_error txn, /Memcached\/set$/, simulated_error_class.name, /No server available/i
    refute_transaction_noticed_error txn, simulated_error_class.name
  end

  def test_get_in_web
    key = set_key_for_testcase

    expected_metrics = expected_web_metrics(:get)

    in_web_transaction("Controller/#{self.class}/action") do
      @cache.get(key)
    end

    assert_memcache_metrics_recorded expected_metrics
  end

  def test_get_multi_in_web
    key = set_key_for_testcase

    expected_metrics = expected_web_metrics(:get_multi)

    in_web_transaction("Controller/#{self.class}/action") do
      @cache.get_multi(key)
    end

    assert_memcache_metrics_recorded expected_metrics
  end

  def test_set_in_web
    expected_metrics = expected_web_metrics(:set)

    in_web_transaction("Controller/#{self.class}/action") do
      @cache.set(randomized_key, "value")
    end

    assert_memcache_metrics_recorded expected_metrics
  end

  def test_add_in_web
    expected_metrics = expected_web_metrics(:add)

    in_web_transaction("Controller/#{self.class}/action") do
      @cache.add(randomized_key, "value")
    end

    assert_memcache_metrics_recorded expected_metrics
  end

  def test_delete_in_web
    key = set_key_for_testcase

    expected_metrics = expected_web_metrics(:delete)

    in_web_transaction("Controller/#{self.class}/action") do
      @cache.delete(key)
    end

    assert_memcache_metrics_recorded expected_metrics
  end

  def test_incr_in_web
    expected_metrics = expected_web_metrics(:incr)

    in_web_transaction("Controller/#{self.class}/action") do
      @cache.incr("incr_test", 0)
    end

    assert_memcache_metrics_recorded expected_metrics
  end

  def test_decr_in_web
    expected_metrics = expected_web_metrics(:decr)

    in_web_transaction("Controller/#{self.class}/action") do
      @cache.decr("decr_test", 1)
    end

    assert_memcache_metrics_recorded expected_metrics
  end

  def test_replace_in_web
    key = set_key_for_testcase

    expected_metrics = expected_web_metrics(:replace)

    in_web_transaction("Controller/#{self.class}/action") do
      @cache.replace(key, 1337807)
    end

    assert_memcache_metrics_recorded expected_metrics
  end

  def test_append_in_web
    key = set_key_for_testcase

    expected_metrics = expected_web_metrics(:append)

    in_web_transaction("Controller/#{self.class}/action") do
      @cache.append(key, 1337807)
    end

    assert_memcache_metrics_recorded expected_metrics
  end

  def test_prepend_in_web
    key = set_key_for_testcase

    expected_metrics = expected_web_metrics(:prepend)

    in_web_transaction("Controller/#{self.class}/action") do
      @cache.prepend(key, 1337807)
    end

    assert_memcache_metrics_recorded expected_metrics
  end

  def test_cas_in_web
    key = set_key_for_testcase(1)

    expected_metrics = expected_web_metrics(:cas)

    in_web_transaction("Controller/#{self.class}/action") do
      @cache.cas(key) {|val| val += 2}
    end

    assert_memcache_metrics_recorded expected_metrics
    assert_equal 3, @cache.get(key)
  end

  def test_get_in_background
    key = set_key_for_testcase

    expected_metrics = expected_bg_metrics(:get)

    in_background_transaction("OtherTransaction/Background/#{self.class}/bg_task") do
      @cache.get(key)
    end

    assert_memcache_metrics_recorded expected_metrics
  end

  def test_get_multi_in_background
    key = set_key_for_testcase

    expected_metrics = expected_bg_metrics(:get_multi)

    in_background_transaction("OtherTransaction/Background/#{self.class}/bg_task") do
      @cache.get_multi(key)
    end

    assert_memcache_metrics_recorded expected_metrics
  end

  def test_set_in_background
    expected_metrics = expected_bg_metrics(:set)

    in_background_transaction("OtherTransaction/Background/#{self.class}/bg_task") do
      @cache.set(randomized_key, "value")
    end

    assert_memcache_metrics_recorded expected_metrics
  end

  def test_add_in_background
    expected_metrics = expected_bg_metrics(:add)

    in_background_transaction("OtherTransaction/Background/#{self.class}/bg_task") do
      @cache.add(randomized_key, "value")
    end

    assert_memcache_metrics_recorded expected_metrics
  end

  def test_delete_in_background
    key = set_key_for_testcase

    expected_metrics = expected_bg_metrics(:delete)

    in_background_transaction("OtherTransaction/Background/#{self.class}/bg_task") do
      @cache.delete(key)
    end

    assert_memcache_metrics_recorded expected_metrics
  end

  def test_incr_in_background
    expected_metrics = expected_bg_metrics(:incr)

    in_background_transaction("OtherTransaction/Background/#{self.class}/bg_task") do
      @cache.incr("incr_test", 0)
    end

    assert_memcache_metrics_recorded expected_metrics
  end

  def test_decr_in_background
    expected_metrics = expected_bg_metrics(:decr)

    in_background_transaction("OtherTransaction/Background/#{self.class}/bg_task") do
      @cache.decr("decr_test", 0)
    end

    assert_memcache_metrics_recorded expected_metrics
  end

  def test_replace_in_background
    key = set_key_for_testcase

    expected_metrics = expected_bg_metrics(:replace)

    in_background_transaction("OtherTransaction/Background/#{self.class}/bg_task") do
      @cache.replace(key, 1337807)
    end

    assert_memcache_metrics_recorded expected_metrics
  end

  def test_append_in_background
    key = set_key_for_testcase

    expected_metrics = expected_bg_metrics(:append)

    in_background_transaction("OtherTransaction/Background/#{self.class}/bg_task") do
      @cache.append(key, 1337807)
    end

    assert_memcache_metrics_recorded expected_metrics
  end

  def test_prepend_in_background
    key = set_key_for_testcase

    expected_metrics = expected_bg_metrics(:prepend)

    in_background_transaction("OtherTransaction/Background/#{self.class}/bg_task") do
      @cache.prepend(key, 1337807)
    end

    assert_memcache_metrics_recorded expected_metrics
  end

  def test_cas_in_background
    key = set_key_for_testcase(1)
    expected_metrics = expected_bg_metrics(:cas)

    in_background_transaction("OtherTransaction/Background/#{self.class}/bg_task") do
      @cache.cas(key) {|val| val += 2}
    end

    assert_memcache_metrics_recorded expected_metrics
    assert_equal 3, @cache.get(key)
  end

  def test_get_in_web_with_capture_memcache_keys
    with_config(:capture_memcache_keys => true) do
      key = set_key_for_testcase
      in_web_transaction("Controller/#{self.class}/action") do
        @cache.get(key)
      end
      trace = last_transaction_trace
      segment = find_node_with_name trace, 'Datastore/operation/Memcached/get'
      assert_equal "get \"#{key}\"", segment[:statement]
    end
  end

end
