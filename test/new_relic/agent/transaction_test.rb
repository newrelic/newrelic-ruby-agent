# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class NewRelic::Agent::TransactionTest < Minitest::Test

  def setup
    @stats_engine = NewRelic::Agent.instance.stats_engine
    @stats_engine.reset!
    NewRelic::Agent.instance.error_collector.reset!
  end

  def teardown
    # Failed transactions can leave partial stack, so pave it for next test

    ::NewRelic::Agent.logger.clear_already_logged
    cleanup_transaction
  end

  def cleanup_transaction
    NewRelic::Agent::TransactionState.tl_clear_for_testing
  end

  def test_request_parsing__none
    in_transaction do |txn|
      assert_nil txn.uri
      assert_nil txn.referer
    end
  end

  def test_request_parsing__path
    in_transaction do |txn|
      request = stub(:path => '/path?hello=bob#none')
      txn.request = request
      assert_equal "/path", txn.uri
    end
  end

  def test_request_parsing__fullpath
    in_transaction do |txn|
      request = stub(:fullpath => '/path?hello=bob#none')
      txn.request = request
      assert_equal "/path", txn.uri
    end
  end

  def test_request_parsing__referer
    in_transaction do |txn|
      request = stub(:referer => 'https://www.yahoo.com:8080/path/hello?bob=none&foo=bar')
      txn.request = request
      assert_nil txn.uri
      assert_equal "https://www.yahoo.com:8080/path/hello", txn.referer
    end
  end

  def test_request_parsing__uri
    in_transaction do |txn|
      request = stub(:uri => 'http://creature.com/path?hello=bob#none', :referer => '/path/hello?bob=none&foo=bar')
      txn.request = request
      assert_equal "/path", txn.uri
      assert_equal "/path/hello", txn.referer
    end
  end

  def test_request_parsing__hostname_only
    in_transaction do |txn|
      request = stub(:uri => 'http://creature.com')
      txn.request = request
      assert_equal "/", txn.uri
      assert_nil txn.referer
    end
  end

  def test_request_parsing__slash
    in_transaction do |txn|
      request = stub(:uri => 'http://creature.com/')
      txn.request = request
      assert_equal "/", txn.uri
      assert_nil txn.referer
    end
  end

  def test_queue_time
    in_transaction do |txn|
      txn.apdex_start = 1000
      txn.start_time = 1500
      assert_equal 500, txn.queue_time
    end
  end

  def test_apdex_bucket_counts_errors_as_frustrating
    bucket = NewRelic::Agent::Transaction.apdex_bucket(0.1, true, 2)
    assert_equal(:apdex_f, bucket)
  end

  def test_apdex_bucket_counts_values_under_apdex_t_as_satisfying
    bucket = NewRelic::Agent::Transaction.apdex_bucket(0.5, false, 1)
    assert_equal(:apdex_s, bucket)
  end

  def test_apdex_bucket_counts_values_of_1_to_4x_apdex_t_as_tolerating
    bucket = NewRelic::Agent::Transaction.apdex_bucket(1.01, false, 1)
    assert_equal(:apdex_t, bucket)
    bucket = NewRelic::Agent::Transaction.apdex_bucket(3.99, false, 1)
    assert_equal(:apdex_t, bucket)
  end

  def test_apdex_bucket_count_values_over_4x_apdex_t_as_frustrating
    bucket = NewRelic::Agent::Transaction.apdex_bucket(4.01, false, 1)
    assert_equal(:apdex_f, bucket)
  end

  def test_has_correct_apdex_t_for_transaction
    config = {
      :web_transactions_apdex => {'Controller/foo/bar' => 1.5},
      :apdex_t => 2.0
    }

    with_config(config) do
      in_transaction('Controller/foo/bar') do |txn|
        assert_equal 1.5, txn.apdex_t
      end

      in_transaction('Controller/some/other') do |txn|
        assert_equal 2.0, txn.apdex_t
      end
    end
  end

  KEY_TRANSACTION_CONFIG = {
      :web_transactions_apdex => {
        'Controller/slow/txn' => 4,
      },
      :apdex => 1
  }

  def test_update_apdex_records_correct_apdex_for_key_transaction
    t0 = freeze_time

    with_config(KEY_TRANSACTION_CONFIG) do
      in_web_transaction('Controller/slow/txn') do
        state = NewRelic::Agent::TransactionState.tl_get
        txn = state.current_transaction
        txn.record_apdex(state, t0 +  3.5)
        txn.record_apdex(state, t0 +  5.5)
        txn.record_apdex(state, t0 + 16.5)
      end

      # apdex_s is 2 because the transaction itself records apdex
      assert_metrics_recorded(
        'Apdex'          => { :apdex_s => 2, :apdex_t => 1, :apdex_f => 1 },
        'Apdex/slow/txn' => { :apdex_s => 2, :apdex_t => 1, :apdex_f => 1 }
      )
    end
  end

  def test_update_apdex_records_correct_apdex_for_non_key_transaction
    t0 = freeze_time

    with_config(KEY_TRANSACTION_CONFIG) do
      in_web_transaction('Controller/other/txn') do
        state = NewRelic::Agent::TransactionState.tl_get
        txn = state.current_transaction
        txn.record_apdex(state, t0 + 0.5)
        txn.record_apdex(state, t0 + 2)
        txn.record_apdex(state, t0 + 5)
      end

      # apdex_s is 2 because the transaction itself records apdex
      assert_metrics_recorded(
        'Apdex'           => { :apdex_s => 2, :apdex_t => 1, :apdex_f => 1 },
        'Apdex/other/txn' => { :apdex_s => 2, :apdex_t => 1, :apdex_f => 1 }
      )
    end
  end

  def test_record_apdex_stores_apdex_t_in_min_and_max
    with_config(:apdex_t => 2.5) do
      in_web_transaction('Controller/some/txn') do
        state = NewRelic::Agent::TransactionState.tl_get
        txn = state.current_transaction
        txn.record_apdex(state, Time.now)
      end
    end

    expected = { :min_call_time => 2.5, :max_call_time => 2.5 }
    assert_metrics_recorded(
      'Apdex' => expected,
      'Apdex/some/txn' => expected
    )
  end

  class SillyError < StandardError
  end

  def test_apdex_success_with_ignored_error
    filter = Proc.new do |error|
      error.is_a?(SillyError) ? nil : error
    end

    with_ignore_error_filter(filter) do
      txn_name = 'Controller/whatever'
      in_web_transaction(txn_name) do
        NewRelic::Agent::Transaction.notice_error(SillyError.new)
      end

      in_web_transaction(txn_name) do
        NewRelic::Agent::Transaction.notice_error(RuntimeError.new)
      end
    end

    assert_metrics_recorded(
      'Apdex'          => { :apdex_s => 1, :apdex_t => 0, :apdex_f => 1 },
      'Apdex/whatever' => { :apdex_s => 1, :apdex_t => 0, :apdex_f => 1 }
    )
  end

  def test_apdex_success_with_config_ignored_error
    txn_name = 'Controller/whatever'
    with_config(:'error_collector.ignore_errors' => SillyError.name) do
      in_web_transaction(txn_name) do
        NewRelic::Agent::Transaction.notice_error(SillyError.new)
      end

      in_web_transaction(txn_name) do
        NewRelic::Agent::Transaction.notice_error(RuntimeError.new)
      end

      assert_metrics_recorded(
        'Apdex'          => { :apdex_s => 1, :apdex_t => 0, :apdex_f => 1 },
        'Apdex/whatever' => { :apdex_s => 1, :apdex_t => 0, :apdex_f => 1 }
      )
    end
  end

  def test_name_is_unset_if_nil
    in_transaction(:transaction_name => nil) do |txn|
      assert !txn.name_set?
    end
  end

  def test_name_set_if_anything_else
    in_transaction("anything else") do |txn|
      assert txn.name_set?
    end
  end

  def test_set_default_transaction_name_without_category
    in_transaction('foo', :category => :controller) do |txn|
      NewRelic::Agent::Transaction.set_default_transaction_name('bar')
      assert_equal("Controller/bar", txn.best_name)
      assert_equal("Controller/bar", txn.frame_stack.last.name)
    end
  end

  def test_set_default_transaction_name_with_category
    in_transaction('foo', :category => :controller) do |txn|
      NewRelic::Agent::Transaction.set_default_transaction_name('bar', :rack)
      assert_equal("Controller/Rack/bar", txn.best_name)
      assert_equal("Controller/Rack/bar", txn.frame_stack.last.name)
    end
  end

  def test_set_default_transaction_name_with_category_and_segment_name
    in_transaction('foo', :category => :controller) do |txn|
      NewRelic::Agent::Transaction.set_default_transaction_name('bar', :grape, 'baz')
      assert_equal("Controller/Grape/bar", txn.best_name)
      assert_equal("baz", txn.frame_stack.last.name)
    end
  end

  def test_generates_guid_on_initialization
    in_transaction do |txn|
      refute_empty txn.guid
    end
  end

  def test_end_applies_transaction_name_rules
    rules = [
      {
        'match_expression' => '[0-9]+',
        'replacement'      => '*',
        'replace_all'      => true
      }
    ]

    with_transaction_renaming_rules(rules) do
      in_transaction('Controller/foo/1/bar/22') do |txn|
        NewRelic::Agent::Transaction.tl_current.freeze_name_and_execute_if_not_ignored
        assert_equal 'Controller/foo/*/bar/*', txn.best_name
      end
    end
  end

  def test_end_fires_a_transaction_finished_event
    name, timestamp, duration = nil
    NewRelic::Agent.subscribe(:transaction_finished) do |payload|
      name = payload[:name]
      timestamp = payload[:start_timestamp]
      duration = payload[:duration]
    end

    start_time = freeze_time
    in_web_transaction('Controller/foo/1/bar/22') do
      advance_time(5)
      NewRelic::Agent::Transaction.tl_current.freeze_name_and_execute_if_not_ignored
    end

    assert_equal 'Controller/foo/1/bar/22', name
    assert_equal start_time.to_f, timestamp
    assert_equal 5.0, duration
  end

  def test_end_fires_a_transaction_finished_event_with_overview_metrics
    freeze_time
    options = nil
    NewRelic::Agent.subscribe(:transaction_finished) do |payload|
      options = payload[:metrics]
    end

    in_web_transaction('Controller/foo/1/bar/22') do
      NewRelic::Agent.record_metric("HttpDispatcher", 2.1)
    end

    assert_equal 2.1, options['HttpDispatcher'].total_call_time
  end

  def test_end_fires_a_transaction_finished_event_with_custom_params
    options = nil
    NewRelic::Agent.subscribe(:transaction_finished) do |payload|
      options = payload[:custom_params]
    end

    in_web_transaction('Controller/foo/1/bar/22') do
      NewRelic::Agent.add_custom_parameters('fooz' => 'barz')
    end

    assert_equal 'barz', options['fooz']
  end

  def test_end_fires_a_transaction_finished_event_with_transaction_guid
    guid = nil
    NewRelic::Agent.subscribe(:transaction_finished) do |payload|
      guid = payload[:guid]
    end

    in_transaction do
      NewRelic::Agent::TransactionState.tl_get.is_cross_app_caller = true
    end

    refute_empty guid
  end

  def test_end_fires_a_transaction_finished_event_without_transaction_guid_if_not_cross_app
    found_guid = :untouched
    NewRelic::Agent.subscribe(:transaction_finished) do |payload|
      found_guid = payload.key?(:guid)
    end

    in_transaction do
      NewRelic::Agent::TransactionState.tl_get.is_cross_app_caller = false
    end

    refute found_guid
  end

  def test_end_fires_a_transaction_finished_event_with_guid_if_referring_transaction
    guid = nil
    NewRelic::Agent.subscribe(:transaction_finished) do |payload|
      guid = payload[:guid]
    end

    with_config(:apdex_t => 2.0) do
      in_transaction do
        state = NewRelic::Agent::TransactionState.tl_get
        state.referring_transaction_info = ["another"]
      end
    end

    refute_empty guid
  end

  def test_end_fires_a_transaction_finished_event_with_referring_transaction_guid
    referring_guid = nil
    NewRelic::Agent.subscribe(:transaction_finished) do |payload|
      referring_guid = payload[:referring_transaction_guid]
    end

    in_transaction do
      NewRelic::Agent::TransactionState.tl_get.referring_transaction_info = ["GUID"]
    end

    assert_equal "GUID", referring_guid
  end

  def test_end_fires_a_transaction_finished_event_without_referring_guid_if_not_present
    found_referring_guid = :untouched
    NewRelic::Agent.subscribe(:transaction_finished) do |payload|
      found_referring_guid = payload.key?(:referring_transaction_guid)
    end

    in_transaction do
      # Make sure we don't have referring transaction state floating around
      NewRelic::Agent::TransactionState.tl_get.referring_transaction_info = nil
    end

    refute found_referring_guid
  end

  def test_end_fires_a_transaction_finished_event_with_apdex_perf_zone
    apdex = nil
    NewRelic::Agent.subscribe(:transaction_finished) do |payload|
      apdex = payload[:apdex_perf_zone]
    end

    freeze_time

    with_config(:apdex_t => 1.0) do
      in_web_transaction { advance_time 0.5 }
      assert_equal('S', apdex)

      in_web_transaction { advance_time 1.5 }
      assert_equal('T', apdex)

      in_web_transaction { advance_time 4.5 }
      assert_equal('F', apdex)
    end
  end

  def test_background_transaction_event_doesnt_include_apdex_perf_zone
    apdex = nil
    NewRelic::Agent.subscribe(:transaction_finished) do |payload|
      apdex = payload[:apdex_perf_zone]
    end

    freeze_time

    with_config(:apdex_t => 1.0) do
      in_background_transaction { advance_time 0.5 }
      assert_nil apdex
    end
  end

  def test_guid_in_finish_event_payload_if_incoming_synthetics_header
    keys = []
    NewRelic::Agent.subscribe(:transaction_finished) do |payload|
      keys = payload.keys
    end

    raw_synthetics_header = 'dummy data'
    synthetics_payload    = [123, 456, 789, 111]

    in_transaction do |txn|
      txn.raw_synthetics_header = raw_synthetics_header
      txn.synthetics_payload    = synthetics_payload
    end

    assert_includes keys, :guid
  end

  def test_cross_app_fields_in_finish_event_payload
    keys = []
    NewRelic::Agent.subscribe(:transaction_finished) do |payload|
      keys = payload.keys
    end

    in_transaction do
      NewRelic::Agent::TransactionState.tl_get.is_cross_app_caller = true
    end

    assert_includes keys, :cat_trip_id
    assert_includes keys, :cat_path_hash
  end

  def test_cross_app_fields_not_in_finish_event_payload_if_no_cross_app_calls
    keys = []
    NewRelic::Agent.subscribe(:transaction_finished) do |payload|
      keys = payload.keys
    end

    freeze_time

    in_transaction do
      advance_time(10)

      state = NewRelic::Agent::TransactionState.tl_get
      state.is_cross_app_caller = false
    end

    refute_includes keys, :cat_trip_id
    refute_includes keys, :cat_path_hash
  end

  def test_is_not_synthetic_request_without_payload
    in_transaction do |txn|
      txn.raw_synthetics_header = ""
      refute txn.is_synthetics_request?
    end
  end

  def test_is_not_synthetic_request_without_header
    in_transaction do |txn|
      txn.synthetics_payload = [1,2,3,4,5]
      refute txn.is_synthetics_request?
    end
  end

  def test_is_synthetic_request
    in_transaction do |txn|
      txn.raw_synthetics_header = ""
      txn.synthetics_payload = [1,2,3,4,5]
      assert txn.is_synthetics_request?
    end
  end

  def test_synthetics_accessors
    in_transaction do
      state = NewRelic::Agent::TransactionState.tl_get
      txn = state.current_transaction
      txn.synthetics_payload = [1,2,3,4,5]

      assert_equal 1, txn.synthetics_version
      assert_equal 2, txn.synthetics_account_id
      assert_equal 3, txn.synthetics_resource_id
      assert_equal 4, txn.synthetics_job_id
      assert_equal 5, txn.synthetics_monitor_id
    end
  end

  def test_synthetics_fields_in_finish_event_payload
    keys = []
    NewRelic::Agent.subscribe(:transaction_finished) do |payload|
      keys = payload.keys
    end

    in_transaction do |txn|
      txn.raw_synthetics_header = "something"
      txn.synthetics_payload = [1, 1, 100, 200, 300]
    end

    assert_includes keys, :synthetics_resource_id
    assert_includes keys, :synthetics_job_id
    assert_includes keys, :synthetics_monitor_id
  end

  def test_synthetics_fields_not_in_finish_event_payload_if_no_cross_app_calls
    keys = []
    NewRelic::Agent.subscribe(:transaction_finished) do |payload|
      keys = payload.keys
    end

    in_transaction do |txn|
      # Make totally sure we're not synthetic
      txn.raw_synthetics_header = nil
    end

    refute_includes keys, :synthetics_resource_id
    refute_includes keys, :synthetics_job_id
    refute_includes keys, :synthetics_monitor_id
  end
  def test_logs_warning_if_a_non_hash_arg_is_passed_to_add_custom_params
    expects_logging(:warn, includes("add_custom_parameters"))
    in_transaction do
      NewRelic::Agent.add_custom_parameters('fooz')
    end
  end

  def test_ignores_custom_parameters_when_in_high_security
    with_config(:high_security => true) do
      in_transaction do |txn|
        NewRelic::Agent.add_custom_parameters(:failure => "is an option")
        assert_empty txn.custom_parameters
      end
    end
  end

  def test_user_attributes_alias_to_custom_parameters
    in_transaction('user_attributes') do |txn|
      txn.set_user_attributes(:set_instance => :set_instance)
      txn.user_attributes[:indexer_instance] = :indexer_instance

      txn.set_user_attributes(:set_class => :set_class)
      txn.user_attributes[:indexer_class] = :indexer_class

      assert_has_custom_parameter(txn, :set_instance)
      assert_has_custom_parameter(txn, :indexer_instance)

      assert_has_custom_parameter(txn, :set_class)
      assert_has_custom_parameter(txn, :indexer_class)
    end
  end

  def test_notice_error_in_current_transaction_saves_it_for_finishing
    in_transaction('failing') do |txn|
      NewRelic::Agent::Transaction.notice_error("")
      assert_equal 1, txn.exceptions.count
    end
  end

  def test_notice_error_after_current_transaction_notifies_error_collector
    in_transaction('failing') do
      # no-op
    end
    NewRelic::Agent::Transaction.notice_error("")
    assert_equal 1, NewRelic::Agent.instance.error_collector.errors.count
  end

  def test_notice_error_without_transaction_notifies_error_collector
    cleanup_transaction
    NewRelic::Agent::Transaction.notice_error("")
    assert_equal 1, NewRelic::Agent.instance.error_collector.errors.count
  end

  def test_records_gc_time
    gc_start = mock('gc start')
    gc_end   = mock('gc end')
    NewRelic::Agent::StatsEngine::GCProfiler.stubs(:take_snapshot).returns(gc_start, gc_end)

    txn = in_transaction do |transaction|
      NewRelic::Agent::StatsEngine::GCProfiler.expects(:record_delta).with(gc_start, gc_end).returns(42)
      transaction
    end

    trace = txn.transaction_trace
    assert_equal(42, trace.params[:custom_params][:gc_time])
  end

  def test_freeze_name_and_execute_if_not_ignored_executes_given_block_if_not_ignored
    NewRelic::Agent.instance.transaction_rules.expects(:rename).
                                               returns('non-ignored-transaction')
    in_transaction('non-ignored-transaction') do |txn|
      block_was_called = false
      txn.freeze_name_and_execute_if_not_ignored do
        block_was_called = true
      end

      assert block_was_called
    end
  end

  def test_freeze_name_and_execute_if_not_ignored_ignores_given_block_if_transaction_ignored
    NewRelic::Agent.instance.transaction_rules.expects(:rename).
                                               returns(nil)
    in_transaction('ignored-transaction') do |txn|
      block_was_called = false
      txn.freeze_name_and_execute_if_not_ignored do
        block_was_called = true
      end

      refute block_was_called
    end
  end

  def test_record_transaction_cpu_positive
    in_transaction do |txn|
      state = NewRelic::Agent::TransactionState.tl_get
      txn.expects(:cpu_burn).twice.returns(1.0)
      NewRelic::Agent.instance.transaction_sampler.expects(:notice_transaction_cpu_time).twice.with(state, 1.0)
      txn.record_transaction_cpu(state)
    end
  end

  def test_record_transaction_cpu_negative
    in_transaction do |txn|
      state = NewRelic::Agent::TransactionState.tl_get
      txn.expects(:cpu_burn).twice.returns(nil)
      # should not be called for the nil case
      NewRelic::Agent.instance.transaction_sampler.expects(:notice_transaction_cpu_time).never
      txn.record_transaction_cpu(state)
    end
  end

  def test_normal_cpu_burn_positive
    in_transaction do |txn|
      txn.instance_variable_set(:@process_cpu_start, 3)
      txn.expects(:process_cpu).twice.returns(4)
      assert_equal 1, txn.normal_cpu_burn
    end
  end

  def test_normal_cpu_burn_negative
    in_transaction do |txn|
      txn.instance_variable_set(:@process_cpu_start, nil)
      txn.expects(:process_cpu).never
      assert_equal nil, txn.normal_cpu_burn
    end
  end

  def test_jruby_cpu_burn_negative
    in_transaction do |txn|
      txn.instance_variable_set(:@jruby_cpu_start, nil)
      txn.expects(:jruby_cpu_time).never
      assert_equal nil, txn.jruby_cpu_burn
    end
  end

  module ::Java
    module JavaLangManagement
      class ManagementFactory
      end
    end
  end

  def test_jruby_cpu_time_returns_0_for_neg1_java_utime
    in_transaction do |txn|
      with_java_classes_loaded do
        bean = mock(:getCurrentThreadUserTime => -1)
        bean.stubs(:isCurrentThreadCpuTimeSupported).returns(true)
        ::Java::JavaLangManagement::ManagementFactory.stubs(:getThreadMXBean).returns(bean)
        assert_equal 0.0, txn.send(:jruby_cpu_time)
      end
    end
  end

  def test_jruby_cpu_time_returns_java_utime_over_1e9_if_java_utime_is_1
    java_utime = 1
    in_transaction do |txn|
      with_java_classes_loaded do
        bean = stub(:getCurrentThreadUserTime => java_utime)
        bean.stubs(:isCurrentThreadCpuTimeSupported).returns(true)
        ::Java::JavaLangManagement::ManagementFactory.stubs(:getThreadMXBean).returns(bean)
        assert_equal java_utime/1e9, txn.send(:jruby_cpu_time)
      end
    end
  end

  def test_jruby_cpu_time_logs_errors_once_at_warn
    in_transaction do |txn|
      with_java_classes_loaded do
        bean = mock
        bean.stubs(:isCurrentThreadCpuTimeSupported).returns(true)
        bean.stubs(:getCurrentThreadUserTime).raises(StandardError, 'Error calculating JRuby CPU Time')
        ::Java::JavaLangManagement::ManagementFactory.stubs(:getThreadMXBean).returns(bean)

        expects_logging(:warn, includes("Error calculating JRuby CPU Time"), any_parameters)
        txn.send(:jruby_cpu_time)
        expects_no_logging(:warn)
        txn.send(:jruby_cpu_time)
      end
    end
  end

  def test_jruby_cpu_time_always_logs_errors_at_debug
    in_transaction do |txn|
      with_java_classes_loaded do
        bean = mock
        bean.stubs(:isCurrentThreadCpuTimeSupported).returns(true)
        bean.stubs(:getCurrentThreadUserTime).raises(StandardError, 'Error calculating JRuby CPU Time')
        ::Java::JavaLangManagement::ManagementFactory.stubs(:getThreadMXBean).returns(bean)

        expects_logging(:warn, includes("Error calculating JRuby CPU Time"), any_parameters)
        txn.send(:jruby_cpu_time)
        expects_logging(:debug, includes("Error calculating JRuby CPU Time"), any_parameters)
        txn.send(:jruby_cpu_time)
      end
    end
  end

  def test_jruby_cpu_time_returns_nil_if_current_thread_user_time_raises
    in_transaction do |txn|
      with_java_classes_loaded do
        bean = mock
        bean.stubs(:isCurrentThreadCpuTimeSupported).returns(true)
        bean.stubs(:getCurrentThreadUserTime).raises(StandardError, 'Error calculating JRuby CPU Time')
        ::Java::JavaLangManagement::ManagementFactory.stubs(:getThreadMXBean).returns(bean)

        assert_nil txn.send(:jruby_cpu_time)
      end
    end
  end

  def test_jruby_cpu_time_does_not_call_get_current_thread_user_time_if_unsupported
    in_transaction do |txn|
      with_java_classes_loaded do
        bean = mock
        bean.stubs(:isCurrentThreadCpuTimeSupported).returns(false)
        ::Java::JavaLangManagement::ManagementFactory.stubs(:getThreadMXBean).returns(bean)
        bean.expects(:getCurrentThreadUserTime).never

        assert_nil txn.send(:jruby_cpu_time)
      end
    end
  end

  def with_java_classes_loaded
    # class_variable_set is private on 1.8.7 :(
    ::NewRelic::Agent::Transaction.send(:class_variable_set, :@@java_classes_loaded, true)
    yield
  ensure
    ::NewRelic::Agent::Transaction.send(:class_variable_set, :@@java_classes_loaded, false)
  end

  def test_cpu_burn_normal
    in_transaction do |txn|
      txn.expects(:normal_cpu_burn).twice.returns(1)
      txn.expects(:jruby_cpu_burn).never
      assert_equal 1, txn.cpu_burn
    end
  end

  def test_cpu_burn_jruby
    in_transaction do |txn|
      txn.expects(:normal_cpu_burn).twice.returns(nil)
      txn.expects(:jruby_cpu_burn).twice.returns(2)
      assert_equal 2, txn.cpu_burn
    end
  end

  def test_transaction_takes_child_name_if_similar_category
    in_transaction('Controller/parent', :category => :sinatra) do
      in_transaction('Controller/child', :category => :controller) do
      end
    end

    assert_metrics_recorded(['Controller/child'])
  end

  def test_transaction_doesnt_take_child_name_if_different_category
    in_transaction('Controller/parent', :category => :sinatra) do
      in_transaction('Whatever/child', :category => :task) do
      end
    end

    assert_metrics_recorded(['Controller/parent'])
  end

  def test_transaction_should_take_child_name_if_frozen_early
    in_transaction('Controller/parent', :category => :sinatra) do
      in_transaction('Controller/child', :category => :controller) do |txn|
        txn.freeze_name_and_execute_if_not_ignored
      end
    end

    assert_metrics_recorded(['Controller/child'])
  end

  def test_ignored_returns_false_if_a_transaction_is_not_ignored
    in_transaction('Controller/test', :category => :sinatra) do |txn|
      refute txn.ignore?
    end
  end

  def test_ignored_returns_true_for_an_ignored_transaction
    in_transaction('Controller/test', :category => :sinatra) do |txn|
      txn.ignore!
      assert txn.ignore?
    end
  end

  def test_ignore_apdex_returns_true_if_apdex_is_ignored
    in_transaction('Controller/test', :category => :sinatra) do |txn|
      txn.ignore_apdex!
      assert txn.ignore_apdex?
    end
  end

  def test_ignore_apdex_returns_false_if_apdex_is_not_ignored
    in_transaction('Controller/test', :category => :sinatra) do |txn|
      refute txn.ignore_apdex?
    end
  end

  def test_ignore_enduser_returns_true_if_enduser_is_ignored
    in_transaction('Controller/test', :category => :sinatra) do  |txn|
      txn.ignore_enduser!
      assert txn.ignore_enduser?
    end
  end

  def test_ignore_enduser_returns_false_if_enduser_is_not_ignored
    in_transaction('Controller/test', :category => :sinatra) do |txn|
      refute txn.ignore_enduser?
    end
  end

  def test_ignored_transactions_do_not_record_metrics
    in_transaction('Controller/test', :category => :sinatra) do |txn|
      txn.ignore!
    end

    assert_metrics_not_recorded(['Controller/test'])
  end

  def test_nested_transactions_are_ignored_if_nested_transaction_is_ignored
    in_transaction('Controller/parent', :category => :sinatra) do
      in_transaction('Controller/child', :category => :controller) do |txn|
        txn.ignore!
      end
    end

    assert_metrics_not_recorded(['Controller/sinatra', 'Controller/child'])
  end

  def test_nested_transactions_are_ignored_if_double_nested_transaction_is_ignored
    in_transaction('Controller/parent', :category => :sinatra) do
      in_transaction('Controller/toddler', :category => :controller) do
        in_transaction('Controller/infant', :category => :controller) do |txn|
          txn.ignore!
        end
      end
    end

    assert_metrics_not_recorded(['Controller/sinatra', 'Controller/toddler', 'Controller/infant'])
  end

  def test_nested_other_transaction
    in_transaction('OtherTransaction/outer', :category => :task) do
      in_transaction('OtherTransaction/inner', :category => :task) do
      end
    end

    assert_metrics_recorded(['OtherTransaction/inner'])
    assert_metrics_not_recorded(['OtherTransaction/outer'])
  end

  def test_failure_during_ignore_error_filter_doesnt_prevent_transaction
    filter = Proc.new do |*_|
      raise "HAHAHAHAH, error in the filter for ignoring errors!"
    end

    with_ignore_error_filter(filter) do
      expects_logging(:error, includes("HAHAHAHAH"), any_parameters)

      in_transaction("Controller/boom") do
        NewRelic::Agent::Transaction.notice_error(SillyError.new)
      end

      assert_metrics_recorded('Controller/boom')
    end
  end

  def test_multiple_similar_errors_in_transaction_do_not_crash
    error_class = Class.new(StandardError) do
      def ==(other)
        self.message == other.message
      end
    end

    in_transaction do |txn|
      e0 = error_class.new('err')
      e1 = error_class.new('err')
      assert_equal(e0, e1)
      txn.notice_error(e0)
      txn.notice_error(e1)
    end

    assert_metrics_recorded('Errors/all' => { :call_count => 2 })
  end

  def test_start_safe_from_exceptions
    NewRelic::Agent::Transaction.any_instance.stubs(:start).raises("Haha")
    expects_logging(:error, any_parameters)

    in_transaction("Controller/boom") do
      # nope
    end

    # We expect our transaction to fail, but no exception should surface
    assert_metrics_not_recorded(['Controller/boom'])
  end

  def test_stop_safe_from_exceptions
    NewRelic::Agent::Transaction.any_instance.stubs(:stop).raises("Haha")
    expects_logging(:error, any_parameters)

    in_transaction("Controller/boom") do
      # nope
    end

    # We expect our transaction to fail, but no exception should surface
    assert_metrics_not_recorded(['Controller/boom'])
  end

  def test_stop_safe_when_no_transaction_available
    expects_logging(:error, includes(NewRelic::Agent::Transaction::FAILED_TO_STOP_MESSAGE))

    state = NewRelic::Agent::TransactionState.new
    NewRelic::Agent::Transaction.stop(state)
  end

  def test_user_defined_rules_ignore_returns_true_for_matched_uri
    rule = 'ignored'
    with_config(:rules => { :ignore_url_regexes => [rule] }) do
      in_transaction do |txn|
        txn.stubs(:uri).returns(rule + '/uri')
        assert txn.user_defined_rules_ignore?, "URIs should be ignored based on user defined rules. Rule: '#{rule}', URI: '#{txn.uri}'."
      end
    end
  end

  def test_stop_ignores_transactions_from_ignored_uris
    with_config(:rules => { :ignore_url_regexes => ['ignored/uri'] }) do
      in_transaction do |txn|
        txn.stubs(:uri).returns('ignored/uri')
        txn.expects(:ignore!)
      end
    end
  end

  def test_transactions_are_not_ignored_if_rules_match_http_auth
    with_config(:rules => { :ignore_url_regexes => ['ignored'] }) do
      in_transaction do |txn|
        txn.stubs(:uri).returns('http://ignored_user:ignored_pass@foo.com/bar/baz')
        txn.expects(:ignore!).never
      end
    end
  end

  def test_transactions_are_not_ignored_if_rules_match_query_string
    with_config(:rules => { :ignore_url_regexes => ['ignored'] }) do
      in_transaction do |txn|
        txn.stubs(:uri).returns('http://foo.com/bar/baz/?ignored=1')
        txn.expects(:ignore!).never
      end
    end
  end

  def test_user_defined_rules_ignore_does_not_parse_the_uri_if_rules_are_empty
    with_config(:rules => { :ignore_url_regexes => [] }) do
      in_transaction do |txn|
        txn.stubs(:uri).returns('http://foo.com/bar/baz')
        NewRelic::Agent::HTTPClients::URIUtil.expects(:parse_url).never
      end
    end
  end

  def test_user_defined_rules_ignore_does_not_filter_the_uri_if_rules_are_empty
    with_config(:rules => { :ignore_url_regexes => [] }) do
      in_transaction do |txn|
        txn.stubs(:uri).returns('http://foo.com/bar/baz')
        NewRelic::Agent::HTTPClients::URIUtil.expects(:filter_uri).never
      end
    end
  end

  def test_user_defined_rules_ignore_logs_uri_parsing_failures
    with_config(:rules => { :ignore_url_regexes => ['notempty'] }) do
      in_transaction do |txn|
        txn.stubs(:uri).returns('http://foo bar.com')
        NewRelic::Agent.logger.expects(:debug)
        NewRelic::Agent.logger.expects(:debug).with(regexp_matches(/foo bar.com/), anything).at_least_once
      end
    end
  end

  def test_user_defined_rules_ignore_returns_false_if_cannot_parse_uri
    with_config(:rules => { :ignore_url_regexes => ['notempty'] }) do
      in_transaction do |txn|
        txn.stubs(:uri).returns('http://foo bar.com')
        refute txn.user_defined_rules_ignore?
      end
    end
  end

  def test_stop_resets_the_transaction_state_if_there_is_an_error
    in_transaction do |txn|
      state = mock
      state.stubs(:current_transaction).raises(StandardError, 'StandardError')

      state.expects(:reset)
      NewRelic::Agent::Transaction.stop(state)
    end
  end

  def test_doesnt_record_queue_time_if_it_is_zero
    in_transaction('boo') do
      # nothing
    end
    assert_metrics_not_recorded(['WebFrontend/QueueTime'])
  end

  def test_doesnt_record_scoped_queue_time_metric
    t0 = freeze_time
    advance_time 10.0
    in_transaction('boo', :apdex_start_time => t0) do
      # nothing
    end
    assert_metrics_recorded('WebFrontend/QueueTime' => { :call_count => 1, :total_call_time => 10.0 })
    assert_metrics_not_recorded(
      [['WebFrontend/QueueTime', 'boo']]
    )
  end

  def test_doesnt_record_crazy_high_queue_times
    t0 = freeze_time(Time.at(10.0))
    advance_time(40 * 365 * 24 * 60 * 60) # 40 years
    in_transaction('boo', :apdex_start_time => t0) do
      # nothing
    end
    assert_metrics_not_recorded(['WebFrontend/QueueTime'])
  end

  def test_background_transactions_with_ignore_rules_are_ok
    with_config(:'rules.ignore_url_regexes' => ['foobar']) do
      in_transaction('foo') do
      end
    end

    assert_metrics_recorded(['foo'])
  end

  def test_transaction_start_sets_default_name_for_transactions_with_matching_categories
    in_transaction('outside_cascade') do
      in_transaction('inside_cascade') do |txn|
        assert_equal 'inside_cascade', txn.best_name
      end
    end
  end

  def test_similar_category?
    web_category1 = NewRelic::Agent::Transaction::WEB_TRANSACTION_CATEGORIES.first
    web_category2 = NewRelic::Agent::Transaction::WEB_TRANSACTION_CATEGORIES.last

    in_transaction('test', :category => web_category1) do |txn|
      assert txn.similar_category?(web_category2)
    end
  end

  def test_similar_category_returns_false_with_mismatched_categories
    web_category = NewRelic::Agent::Transaction::WEB_TRANSACTION_CATEGORIES.first

    in_transaction('test', :category => web_category) do |txn|
      frame = stub(:category => :other)
      refute txn.similar_category?(frame)
    end
  end

  def test_similar_category_returns_true_with_nonweb_categories
    in_transaction('test', :category => :other) do |txn|
      frame = stub(:category => :other)
      assert txn.similar_category?(frame)
    end
  end

  def test_set_overriding_transaction_name_sets_name_from_api
    in_transaction('test') do |txn|
      txn.class.set_overriding_transaction_name('name_from_api', 'category')

      assert_equal 'category/name_from_api', txn.best_name
    end
  end

  def assert_has_custom_parameter(txn, key, value = key)
    assert_equal(value, txn.custom_parameters[key])
  end

  def test_wrap_transaction
    state = NewRelic::Agent::TransactionState.tl_get
    NewRelic::Agent::Transaction.wrap(state, 'test', :other) do
      # No-op
    end

    assert_metrics_recorded(['test'])
  end

  def test_wrap_transaction_with_early_failure
    yielded = false
    state = NewRelic::Agent::TransactionState.tl_get
    NewRelic::Agent::Transaction.any_instance.stubs(:start).raises("Boom")
    NewRelic::Agent::Transaction.wrap(state, 'test', :other) do
      yielded = true
    end

    assert yielded
  end

  def test_wrap_transaction_with_late_failure
    state = NewRelic::Agent::TransactionState.tl_get
    NewRelic::Agent::Transaction.any_instance.stubs(:stop).raises("Boom")
    NewRelic::Agent::Transaction.wrap(state, 'test', :other) do
      # No-op
    end

    refute_metrics_recorded(['test'])
  end

  def test_wrap_transaction_notices_errors
    state = NewRelic::Agent::TransactionState.tl_get
    assert_raises RuntimeError do
      NewRelic::Agent::Transaction.wrap(state, 'test', :other) do
        raise "O_o"
      end
    end

    assert_metrics_recorded(["Errors/all"])
  end
end
