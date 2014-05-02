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
    cleanup_transaction
  end

  def cleanup_transaction
    NewRelic::Agent::TransactionState.clear
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

    with_config(config, :do_not_cast => true) do
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

    with_config(KEY_TRANSACTION_CONFIG, :do_not_cast => true) do
      in_web_transaction('Controller/slow/txn') do
        NewRelic::Agent::Transaction.record_apdex(t0 + 3.5,  false)
        NewRelic::Agent::Transaction.record_apdex(t0 + 5.5,  false)
        NewRelic::Agent::Transaction.record_apdex(t0 + 16.5, false)
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

    with_config(KEY_TRANSACTION_CONFIG, :do_not_cast => true) do
      in_web_transaction('Controller/other/txn') do
        NewRelic::Agent::Transaction.record_apdex(t0 + 0.5, false)
        NewRelic::Agent::Transaction.record_apdex(t0 + 2,   false)
        NewRelic::Agent::Transaction.record_apdex(t0 + 5,   false)
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
        NewRelic::Agent::Transaction.record_apdex(Time.now, false)
      end
    end

    expected = { :min_call_time => 2.5, :max_call_time => 2.5 }
    assert_metrics_recorded(
      'Apdex' => expected,
      'Apdex/some/txn' => expected
    )
  end

  def test_name_is_unset_if_nil
    in_transaction do |txn|
      txn.default_name = nil
      assert !txn.name_set?
    end
  end

  def test_name_set_if_anything_else
    in_transaction("anything else") do |txn|
      assert txn.name_set?
    end
  end

  def test_generates_guid_on_initialization
    in_transaction do |txn|
      refute_empty txn.guid
    end
  end

  def test_end_applies_transaction_name_rules
    in_transaction('Controller/foo/1/bar/22') do |txn|
      rule = NewRelic::Agent::RulesEngine::Rule.new('match_expression' => '[0-9]+',
                                                    'replacement'      => '*',
                                                    'replace_all'      => true)
      NewRelic::Agent.instance.transaction_rules << rule
      NewRelic::Agent::Transaction.freeze_name_and_execute_if_not_ignored
      assert_equal 'Controller/foo/*/bar/*', txn.best_name
    end
  ensure
    NewRelic::Agent.instance.instance_variable_set(:@transaction_rules,
                                              NewRelic::Agent::RulesEngine.new)
  end

  def test_end_fires_a_transaction_finished_event
    name, timestamp, duration, type = nil
    NewRelic::Agent.subscribe(:transaction_finished) do |payload|
      name = payload[:name]
      timestamp = payload[:start_timestamp]
      duration = payload[:duration]
      type = payload[:type]
    end

    start_time = freeze_time
    in_web_transaction('Controller/foo/1/bar/22') do
      advance_time(5)
      NewRelic::Agent::Transaction.freeze_name_and_execute_if_not_ignored
    end

    assert_equal 'Controller/foo/1/bar/22', name
    assert_equal start_time.to_f, timestamp
    assert_equal 5.0, duration
    assert_equal :controller, type
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

    assert_equal 2.1, options[NewRelic::MetricSpec.new('HttpDispatcher')].total_call_time
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
      NewRelic::Agent::TransactionState.get.is_cross_app_caller = true
    end

    refute_empty guid
  end

  def test_end_fires_a_transaction_finished_event_without_transaction_guid_if_not_cross_app
    found_guid = :untouched
    NewRelic::Agent.subscribe(:transaction_finished) do |payload|
      found_guid = payload.key?(:guid)
    end

    in_transaction do
      NewRelic::Agent::TransactionState.get.is_cross_app_caller = false
    end

    refute found_guid
  end

  def test_end_fires_a_transaction_finished_event_with_referring_transaction_guid
    referring_guid = nil
    NewRelic::Agent.subscribe(:transaction_finished) do |payload|
      referring_guid = payload[:referring_transaction_guid]
    end

    in_transaction do
      NewRelic::Agent::TransactionState.get.referring_transaction_info = ["GUID"]
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
      NewRelic::Agent::TransactionState.get.referring_transaction_info = nil
    end

    refute found_referring_guid
  end

  def test_logs_warning_if_a_non_hash_arg_is_passed_to_add_custom_params
    expects_logging(:warn, includes("add_custom_parameters"))
    in_transaction do
      NewRelic::Agent.add_custom_parameters('fooz')
    end
  end

  def test_user_attributes_alias_to_custom_parameters
    in_transaction('user_attributes') do
      txn = NewRelic::Agent::Transaction.current
      txn.set_user_attributes(:set_instance => :set_instance)
      txn.user_attributes[:indexer_instance] = :indexer_instance

      NewRelic::Agent::Transaction.set_user_attributes(:set_class => :set_class)
      NewRelic::Agent::Transaction.user_attributes[:indexer_class] = :indexer_class

      assert_has_custom_parameter(:set_instance)
      assert_has_custom_parameter(:indexer_instance)

      assert_has_custom_parameter(:set_class)
      assert_has_custom_parameter(:indexer_class)
    end
  end

  def test_notice_error_in_current_transaction_saves_it_for_finishing
    in_transaction('failing') do
      NewRelic::Agent::Transaction.notice_error("")
      assert_equal 1, NewRelic::Agent::Transaction.current.exceptions.count
    end
  end

  def test_notice_error_after_current_transaction_notifies_error_collector
    in_transaction('failing') do
      # no-op
    end
    NewRelic::Agent::Transaction.notice_error("")
    assert_equal 1, NewRelic::Agent.instance.error_collector.errors.count
  end

  def test_notice_error_after_current_transaction_gets_custom_params
    in_transaction('failing') do
      NewRelic::Agent.add_custom_parameters(:custom => "parameter")
    end
    NewRelic::Agent::Transaction.notice_error("")

    error = NewRelic::Agent.instance.error_collector.errors.first
    assert_equal({ :custom => "parameter" }, error.params[:custom_params])
  end

  def test_notice_error_after_current_transcation_doesnt_tromp_passed_params
    in_transaction('failing') do
      NewRelic::Agent.add_custom_parameters(:custom => "parameter")
    end
    NewRelic::Agent::Transaction.notice_error("", :custom_params => { :passing => true })

    error = NewRelic::Agent.instance.error_collector.errors.first
    expected = {
      :custom => "parameter",
      :passing => true,
    }
    assert_equal(expected, error.params[:custom_params])
  end

  def test_notice_error_after_current_transaction_gets_name
    in_transaction('failing') do
      #no-op
    end
    NewRelic::Agent::Transaction.notice_error("")
    error = NewRelic::Agent.instance.error_collector.errors.first
    assert_equal 'failing', error.path
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

    txn = in_transaction do
      NewRelic::Agent::StatsEngine::GCProfiler.expects(:record_delta).with(gc_start, gc_end).returns(42)
      NewRelic::Agent::Transaction.current
    end

    trace = txn.transaction_trace
    assert_equal(42, trace.params[:custom_params][:gc_time])
  end

  def test_freeze_name_and_execute_if_not_ignored_executes_given_block_if_not_ignored
    NewRelic::Agent.instance.transaction_rules.expects(:rename).
                                               returns('non-ignored-transaction')
    in_transaction('non-ignored-transaction') do
      block_was_called = false
      NewRelic::Agent::Transaction.freeze_name_and_execute_if_not_ignored do
        block_was_called = true
      end

      assert block_was_called
    end
  end

  def test_freeze_name_and_execute_if_not_ignored_ignores_given_block_if_transaction_ignored
    NewRelic::Agent.instance.transaction_rules.expects(:rename).
                                               returns(nil)
    in_transaction('ignored-transaction') do
      block_was_called = false
      NewRelic::Agent::Transaction.freeze_name_and_execute_if_not_ignored do
        block_was_called = true
      end

      refute block_was_called
    end
  end

  def test_record_transaction_cpu_positive
    in_transaction do |txn|
      txn.expects(:cpu_burn).twice.returns(1.0)
      NewRelic::Agent.instance.transaction_sampler.expects(:notice_transaction_cpu_time).twice.with(1.0)
      txn.record_transaction_cpu
    end
  end

  def test_record_transaction_cpu_negative
    in_transaction do |txn|
      txn.expects(:cpu_burn).twice.returns(nil)
      # should not be called for the nil case
      NewRelic::Agent.instance.transaction_sampler.expects(:notice_transaction_cpu_time).never
      txn.record_transaction_cpu
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

  def test_transaction_takes_child_name_if_similar_type
    in_transaction('Controller/parent', :type => :sinatra) do
      in_transaction('Controller/child', :type => :controller) do
      end
    end

    assert_metrics_recorded(['Controller/child'])
  end

  def test_transaction_doesnt_take_child_name_if_different_type
    in_transaction('Controller/parent', :type => :sinatra) do
      in_transaction('Whatever/child', :type => :task) do
      end
    end

    assert_metrics_recorded(['Controller/parent'])
  end

  def test_transaction_should_take_child_name_if_frozen_early
    in_transaction('Controller/parent', :type => :sinatra) do
      in_transaction('Controller/child', :type => :controller) do |txn|
        txn.freeze_name_and_execute_if_not_ignored
      end
    end

    assert_metrics_recorded(['Controller/child'])
  end

  def assert_has_custom_parameter(key, value = key)
    assert_equal(value, NewRelic::Agent::Transaction.current.custom_parameters[key])
  end

end
