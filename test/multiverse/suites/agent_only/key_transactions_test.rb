# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.join(File.dirname(__FILE__), '..', '..', '..', 'agent_helper')

class KeyTransactionsTest < Test::Unit::TestCase
  class TestWidget
    include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation

    def key_txn
      advance_time(5)
    end
    add_transaction_tracer :key_txn

    def other_txn
      advance_time(5)
    end
    add_transaction_tracer :other_txn
  end

  def setup
    $collector ||= NewRelic::FakeCollector.new
    $collector.reset
    key_apdex_config = { 'Controller/KeyTransactionsTest::TestWidget/key_txn' => 1 }
    $collector.mock['connect'] = [200, {'return_value' => {
                                      "agent_run_id" => 666,
                            'web_transactions_apdex' => key_apdex_config,
                                           'apdex_t' => 10
                                    }}]
    $collector.run

    NewRelic::Agent.manual_start(:sync_startup => true,
                                 :force_reconnect => true)

    freeze_time
  end

  def teardown
    NewRelic::Agent.shutdown
    $collector.reset
  end

  SATISFYING = 0
  TOLERATING = 1
  FAILING    = 2

  def test_applied_correct_apdex_t_to_key_txn
    TestWidget.new.key_txn
    NewRelic::Agent.instance.send(:harvest_and_send_timeslice_data)

    stats = $collector.reported_stats_for_metric('Apdex')[0]
    assert_equal(1.0, stats[FAILING],
                 "Expected stats (#{stats}) to be apdex failing")
  end

  def test_applied_correct_apdex_t_to_regular_txn
    TestWidget.new.other_txn
    NewRelic::Agent.instance.send(:harvest_and_send_timeslice_data)

    stats = $collector.reported_stats_for_metric('Apdex')[0]
    assert_equal(1.0, stats[SATISFYING],
                 "Expected stats (#{stats}) to be apdex satisfying")
  end

  def test_applied_correct_tt_theshold
    TestWidget.new.key_txn
    TestWidget.new.other_txn

    NewRelic::Agent.instance.send(:harvest_and_send_slowest_sample)

    traces = $collector.calls_for('transaction_sample_data')
    assert_equal 1, traces.size
    assert_equal('Controller/KeyTransactionsTest::TestWidget/key_txn',
                 traces[0].metric_name)
  end

  def stub_time_now
    now = Time.now
    Time.stubs(:now).returns(now)
    return now
  end
end
