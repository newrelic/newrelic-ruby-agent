# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class NewRelic::Agent::TransactionTest < Test::Unit::TestCase

  attr_reader :txn

  def setup
    @txn = NewRelic::Agent::Transaction.new
    @stats_engine = NewRelic::Agent.instance.stats_engine
    @stats_engine.reset_stats
  end

  def test_request_parsing__none
    assert_nil txn.uri
    assert_nil txn.referer
  end

  def test_request_parsing__path
    request = stub(:path => '/path?hello=bob#none')
    txn.request = request
    assert_equal "/path", txn.uri
  end

  def test_request_parsing__fullpath
    request = stub(:fullpath => '/path?hello=bob#none')
    txn.request = request
    assert_equal "/path", txn.uri
  end

  def test_request_parsing__referer
    request = stub(:referer => 'https://www.yahoo.com:8080/path/hello?bob=none&foo=bar')
    txn.request = request
    assert_nil txn.uri
    assert_equal "https://www.yahoo.com:8080/path/hello", txn.referer
  end

  def test_request_parsing__uri
    request = stub(:uri => 'http://creature.com/path?hello=bob#none', :referer => '/path/hello?bob=none&foo=bar')
    txn.request = request
    assert_equal "/path", txn.uri
    assert_equal "/path/hello", txn.referer
  end

  def test_request_parsing__hostname_only
    request = stub(:uri => 'http://creature.com')
    txn.request = request
    assert_equal "/", txn.uri
    assert_nil txn.referer
  end

  def test_request_parsing__slash
    request = stub(:uri => 'http://creature.com/')
    txn.request = request
    assert_equal "/", txn.uri
    assert_nil txn.referer
  end

  def test_queue_time
    txn.apdex_start = 1000
    txn.start_time = 1500
    assert_equal 500, txn.queue_time
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
      txn.name = 'Controller/foo/bar'
      assert_equal 1.5, txn.apdex_t

      txn.name = 'Controller/some/other'
      assert_equal 2.0, txn.apdex_t
    end
  end

  def test_update_apdex_records_correct_apdex_for_key_transaction
    config = {
      :web_transactions_apdex => {
        'Controller/slow/txn' => 4,
        'Controller/fast/txn' => 0.1,
      },
      :apdex => 1
    }

    freeze_time
    t0 = Time.now

    # Setting the transaction name from within the in_transaction block seems
    # like cheating, but it mimics the way things are actually done, where we
    # finalize the transaction name before recording the Apdex metrics.
    with_config(config, :do_not_cast => true) do
      in_web_transaction('Controller/slow/txn') do
        NewRelic::Agent::Transaction.current.name = 'Controller/slow/txn'
        NewRelic::Agent::Transaction.record_apdex(t0 + 3.5,  false)
        NewRelic::Agent::Transaction.record_apdex(t0 + 5.5,  false)
        NewRelic::Agent::Transaction.record_apdex(t0 + 16.5, false)
      end
      assert_metrics_recorded(
        'Apdex'          => { :apdex_s => 1, :apdex_t => 1, :apdex_f => 1 },
        'Apdex/slow/txn' => { :apdex_s => 1, :apdex_t => 1, :apdex_f => 1 }
      )

      in_web_transaction('Controller/fast/txn') do
        NewRelic::Agent::Transaction.current.name = 'Controller/fast/txn'
        NewRelic::Agent::Transaction.record_apdex(t0 + 0.05, false)
        NewRelic::Agent::Transaction.record_apdex(t0 + 0.2,  false)
        NewRelic::Agent::Transaction.record_apdex(t0 + 0.5,  false)
      end
      assert_metrics_recorded(
        'Apdex'          => { :apdex_s => 2, :apdex_t => 2, :apdex_f => 2 },
        'Apdex/fast/txn' => { :apdex_s => 1, :apdex_t => 1, :apdex_f => 1 }
      )

      in_web_transaction('Controller/other/txn') do
        NewRelic::Agent::Transaction.current.name = 'Controller/other/txn'
        NewRelic::Agent::Transaction.record_apdex(t0 + 0.5, false)
        NewRelic::Agent::Transaction.record_apdex(t0 + 2,   false)
        NewRelic::Agent::Transaction.record_apdex(t0 + 5,   false)
      end
      assert_metrics_recorded(
        'Apdex'           => { :apdex_s => 3, :apdex_t => 3, :apdex_f => 3 },
        'Apdex/other/txn' => { :apdex_s => 1, :apdex_t => 1, :apdex_f => 1 }
      )
    end
  end

  def test_record_apdex_stores_apdex_t_in_min_and_max
    with_config(:apdex_t => 2.5) do
      in_web_transaction('Controller/some/txn') do
        NewRelic::Agent::Transaction.current.name = 'Controller/some/txn'
        NewRelic::Agent::Transaction.record_apdex(Time.now, false)
      end
    end

    expected = { :min_call_time => 2.5, :max_call_time => 2.5 }
    assert_metrics_recorded(
      'Apdex' => expected,
      'Apdex/some/txn' => expected
    )
  end

  def test_stop_sets_name
    NewRelic::Agent::Transaction.start(:controller)
    txn = NewRelic::Agent::Transaction.stop('new_name')
    assert_equal 'new_name', txn.name
  end

  def test_name_is_unset_if_nil
    txn = NewRelic::Agent::Transaction.new
    txn.name = nil
    assert !txn.name_set?
  end

  def test_name_is_unset_if_unknown
    txn = NewRelic::Agent::Transaction.new
    txn.name = NewRelic::Agent::UNKNOWN_METRIC
    assert !txn.name_set?
  end

  def test_name_set_if_anything_else
    txn = NewRelic::Agent::Transaction.new
    txn.name = "anything else"
    assert txn.name_set?
  end

  def test_start_adds_controller_context_to_txn_stack
    NewRelic::Agent::Transaction.start(:controller)
    assert_equal 1, NewRelic::Agent::Transaction.stack.size

    NewRelic::Agent::Transaction.start(:controller)
    assert_equal 2, NewRelic::Agent::Transaction.stack.size

    NewRelic::Agent::Transaction.stop('txn')
    assert_equal 1, NewRelic::Agent::Transaction.stack.size

    NewRelic::Agent::Transaction.stop('txn')
    assert_equal 0, NewRelic::Agent::Transaction.stack.size
  end

  def test_end_applies_transaction_name_rules
    rule = NewRelic::Agent::RulesEngine::Rule.new('match_expression' => '[0-9]+',
                                                  'replacement'      => '*',
                                                  'replace_all'      => true)
    NewRelic::Agent.instance.transaction_rules << rule
    NewRelic::Agent::Transaction.start(:controller)
    NewRelic::Agent.set_transaction_name('foo/1/bar/22')
    NewRelic::Agent::Transaction.freeze_name
    txn = NewRelic::Agent::Transaction.stop('txn')
    assert_equal 'Controller/foo/*/bar/*', txn.name
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
    NewRelic::Agent::Transaction.start(:controller)
    advance_time(5)
    NewRelic::Agent.set_transaction_name('foo/1/bar/22')
    NewRelic::Agent::Transaction.freeze_name
    NewRelic::Agent::Transaction.stop('txn')

    assert_equal 'Controller/foo/1/bar/22', name
    assert_equal start_time.to_f, timestamp
    assert_equal 5.0, duration
    assert_equal :controller, type
  end

  def test_end_fires_a_transaction_finished_event_with_overview_metrics
    options = nil
    NewRelic::Agent.subscribe(:transaction_finished) do |payload|
      options = payload[:overview_metrics]
    end

    NewRelic::Agent::Transaction.start(:controller)
    NewRelic::Agent.record_metric("HttpDispatcher", 2.1)
    NewRelic::Agent::Transaction.stop('txn')

    assert_equal 2.1, options[:webDuration]
  end

  def test_parent_returns_parent_transaction_if_there_is_one
    txn, outer_txn = nil
    in_transaction('outer') do
      outer_txn = NewRelic::Agent::Transaction.current
      in_transaction('inner') do
        txn = NewRelic::Agent::Transaction.parent
      end
    end
    assert_same(outer_txn, txn)
  end

  def test_parent_returns_nil_if_there_is_no_parent
    txn = 'this is a non-nil placeholder'
    in_transaction('outer') do
      txn = NewRelic::Agent::Transaction.parent
    end
    assert_nil(txn)
  end

  def test_parent_returns_nil_if_outside_transaction_entirely
    assert_nil(NewRelic::Agent::Transaction.parent)
  end
end
