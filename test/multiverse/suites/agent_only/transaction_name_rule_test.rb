class TransactionNameRuleTest < Test::Unit::TestCase
  class TestWidget
    include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation

    def txn
      'doot de doo'
    end
    add_transaction_tracer :txn
  end

  def setup
    $collector ||= NewRelic::FakeCollector.new
    $collector.reset
    rule_specifications = [ { 'match_expression' => 'TransactionNameRuleTest',
                              'replacement' => 'Class' } ]
    $collector.mock['connect'] = [200, {'return_value' => {"agent_run_id" => 666,
                             'transaction_name_rules' => rule_specifications}}]
    $collector.run

    NewRelic::Agent.manual_start(:sync_startup => true,
                                 :force_reconnect => true)
  end

  def teardown
    NewRelic::Agent.shutdown
  end

  def test_transaction_name_rules_are_applied
    TestWidget.new.txn
    metric_names = ::NewRelic::Agent.instance.stats_engine.stats_hash.keys.map{|k| k.name}
    assert(metric_names.include?('Controller/Class::TestWidget/txn'),
           "'Controller/Class::TestWidget/txn' not found in #{metric_names}")
    assert(metric_names.include?('Apdex/Class::TestWidget/txn'),
           "'Apdex/Class::TestWidget/txn' not found in #{metric_names}")
    assert(!metric_names.include?('Controller/TransactionNameRuleTest::TestWidget/txn'),
           "'Controller/TransactionNameRuleTest::TestWidget/txn' should not be in #{metric_names}")
  end
end
