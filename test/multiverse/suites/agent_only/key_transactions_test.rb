class KeyTransactionsTest < Test::Unit::TestCase
  class TestWidget
    include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation

    def key_txn
      sleep 0.5
    end
    add_transaction_tracer :key_txn

    def other_txn
      sleep 0.5
    end
    add_transaction_tracer :other_txn
  end

  def setup
    $collector ||= NewRelic::FakeCollector.new
    $collector.reset
    key_apdex_config = { 'Controller/KeyTransactionsTest::TestWidget/key_txn' => 0.1 }
    $collector.mock['connect'] = [200, {'return_value' => {
                                      "agent_run_id" => 666,
                            'web_transactions_apdex' => key_apdex_config,
                                           'apdex_t' => 1.0
                                    }}]
    $collector.run

    NewRelic::Agent.manual_start(:sync_startup => true,
                                 :force_reconnect => true)
  end

  def teardown
    NewRelic::Agent.shutdown
  end

  SATISFYING = 0
  TOLERATING = 1
  FAILING    = 2

  def test_applied_correct_apdex_t_to_key_txn
    TestWidget.new.key_txn
    NewRelic::Agent.instance.send(:harvest_and_send_timeslice_data)

    stats = $collector.reported_stats_for_metric('Apdex')[0]
    assert_equal 1.0, stats[FAILING]
  end

  def test_applied_correct_apdex_t_to_regular_txn
    TestWidget.new.other_txn
    NewRelic::Agent.instance.send(:harvest_and_send_timeslice_data)

    stats = $collector.reported_stats_for_metric('Apdex')[0]
    assert_equal 1.0, stats[SATISFYING]
  end
end
