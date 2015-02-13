# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module TransactionIgnoringTestCases

  include MultiverseHelpers

  TXN_PREFIX = 'Controller/'

  setup_and_teardown_agent do |collector|
    collector.stub('connect', {
      'transaction_name_rules' => [{"match_expression" => "ignored_transaction",
                                    "ignore"           => true}],
      'agent_run_id' => 1,
    })
  end

  # Test classes that include this module are expected to define:
  #   trigger_transaction(txn_name)
  #   trigger_transaction_with_error(txn_name, error_msg)
  #   trigger_transaction_with_slow_sql(txn_name)


  def test_does_not_record_metrics_for_ignored_transaction
    trigger_transaction('accepted_transaction')
    trigger_transaction('ignored_transaction')

    NewRelic::Agent.instance.send(:harvest_and_send_timeslice_data)

    stats = $collector.reported_stats_for_metric(TXN_PREFIX+'accepted_transaction')
    assert_equal(1, stats.size)

    stats = $collector.reported_stats_for_metric(TXN_PREFIX+'ignored_transaction')
    assert_equal(0, stats.size)
  end

  def test_does_not_record_traced_errors_for_ignored_transactions
    trigger_transaction_with_error('ignored_transaction',  'Buffy dies :(')
    trigger_transaction_with_error('accepted_transaction', 'Buffy lives :)')

    NewRelic::Agent.instance.send(:harvest_and_send_errors)

    posts = $collector.calls_for('error_data')
    assert_equal(1, posts.size)

    errors = posts.first.errors

    assert_equal(1, errors.size)
    assert_equal('Buffy lives :)', errors.first.message)
  end

  def test_does_not_record_transaction_trace_for_ignored_transactions
    with_config(:'transaction_tracer.transaction_threshold' => 0) do
      trigger_transaction('accepted_transaction')
      NewRelic::Agent.instance.send(:harvest_and_send_transaction_traces)
      assert_equal(1, $collector.calls_for('transaction_sample_data').size)

      trigger_transaction('ignored_transaction')
      NewRelic::Agent.instance.send(:harvest_and_send_transaction_traces)
      assert_equal(1, $collector.calls_for('transaction_sample_data').size)
    end
  end

  def test_does_not_record_analytics_for_ignored_transactions
    trigger_transaction('ignored_transaction')
    trigger_transaction('accepted_transaction')

    NewRelic::Agent.instance.send(:harvest_and_send_analytic_event_data)

    posts = $collector.calls_for('analytic_event_data')
    assert_equal(1, posts.size)

    events = posts.first.events

    assert_equal(1, events.size)
    assert_equal(TXN_PREFIX+'accepted_transaction', events.first[0]['name'])
  end

  def test_does_not_record_sql_traces_for_ignored_transactions
    trigger_transaction_with_slow_sql('ignored_transaction')
    trigger_transaction_with_slow_sql('accepted_transaction')

    NewRelic::Agent.instance.send(:harvest_and_send_slowest_sql)

    posts = $collector.calls_for('sql_trace_data')
    assert_equal(1, posts.size)

    traces = posts.first.traces

    assert_equal(1, traces.size)

    trace = traces.first

    # From SqlTrace#to_collector_array
    # 0 -> path
    # 5 -> call_count
    assert_equal(TXN_PREFIX+'accepted_transaction', trace[0])
    assert_equal(1, trace[5])
  end

end
