# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.join(File.dirname(__FILE__), '..', '..', '..', 'agent_helper')
require 'multiverse_helpers'

class KeyTransactionsTest < Minitest::Test

  include MultiverseHelpers

  setup_and_teardown_agent do |collector|
    key_txn_name = 'Controller/KeyTransactionsTest::TestWidget/key_txn'
    collector.stub('connect',
                   {
      'web_transactions_apdex' => { key_txn_name => 1 },
      'apdex_t' => 10
    })
  end

  def after_setup
    freeze_time
  end

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

    NewRelic::Agent.instance.send(:harvest_and_send_transaction_traces)

    traces = $collector.calls_for('transaction_sample_data')
    assert_equal 1, traces.size
    assert_equal('Controller/KeyTransactionsTest::TestWidget/key_txn',
                 traces[0].metric_name)
  end

end
