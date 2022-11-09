# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class KeyTransactionsTest < Minitest::Test
  include MultiverseHelpers

  WEB_KEY_TXN = 'Controller/KeyTransactionsTest::TestWidget/key_txn'
  OTHER_KEY_TXN = 'OtherTransaction/SidekiqJob/JobClass/key_txn'
  OTHER_TXN = 'OtherTransaction/SidekiqJob/JobClass/other_txn'

  setup_and_teardown_agent do |collector|
    collector.stub('connect', {
      'web_transactions_apdex' => {
        WEB_KEY_TXN => 1,
        OTHER_KEY_TXN => 1
      },
      'apdex_t' => 10
    })
  end

  def after_setup
    nr_freeze_process_time
  end

  class TestWidget
    include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation

    def key_txn
      advance_process_time(5)
    end
    add_transaction_tracer :key_txn

    def other_txn
      advance_process_time(5)
    end
    add_transaction_tracer :other_txn
  end

  class TestBackgroundWidget
    def key_txn
      job(OTHER_KEY_TXN)
    end

    def other_txn
      job(OTHER_TXN)
    end

    def job(name)
      ::NewRelic::Agent::Tracer.in_transaction(name: name, category: :other) do
        advance_process_time(5)
      end
    end
  end

  SATISFYING = 0
  TOLERATING = 1
  FAILING = 2

  def test_applied_correct_apdex_t_to_key_txn
    TestWidget.new.key_txn
    NewRelic::Agent.instance.send(:harvest_and_send_timeslice_data)

    stats = $collector.reported_stats_for_metric('Apdex')[0]

    assert_in_delta(1.0, stats[FAILING], 0.001, "Expected stats (#{stats}) to be apdex failing")
  end

  def test_applied_correct_apdex_t_to_regular_txn
    TestWidget.new.other_txn
    NewRelic::Agent.instance.send(:harvest_and_send_timeslice_data)

    stats = $collector.reported_stats_for_metric('Apdex')[0]

    assert_in_delta(1.0, stats[SATISFYING], 0.001, "Expected stats (#{stats}) to be apdex satisfying")
  end

  def test_applied_correct_tt_threshold
    TestWidget.new.key_txn
    TestWidget.new.other_txn

    NewRelic::Agent.instance.send(:harvest_and_send_transaction_traces)

    traces = $collector.calls_for('transaction_sample_data')

    assert_equal 1, traces.size
    assert_equal(WEB_KEY_TXN, traces[0].metric_name)
  end

  def test_applied_correct_apdex_t_to_background_key_txn
    TestBackgroundWidget.new.key_txn
    NewRelic::Agent.instance.send(:harvest_and_send_timeslice_data)

    stats = $collector.reported_stats_for_metric('ApdexOther')[0]

    assert_in_delta(1.0, stats[FAILING], 0.001, "Expected stats (#{stats}) to be apdex failing")
  end

  def test_no_apdex_for_regular_background_txn
    TestBackgroundWidget.new.other_txn
    NewRelic::Agent.instance.send(:harvest_and_send_timeslice_data)

    assert_empty $collector.reported_stats_for_metric('ApdexOther')
  end

  def test_applied_correct_tt_threshold_to_background
    TestBackgroundWidget.new.key_txn
    TestBackgroundWidget.new.other_txn

    NewRelic::Agent.instance.send(:harvest_and_send_transaction_traces)

    traces = $collector.calls_for('transaction_sample_data')

    assert_equal 1, traces.size
    assert_equal(OTHER_KEY_TXN, traces[0].metric_name)
  end
end
