class TransactionNameRuleTest < Test::Unit::TestCase
  class TestWidget
    include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation

    def txn
      mthd
    end
    add_transaction_tracer :txn

    def mthd
      'doot de doo'
    end
    add_method_tracer :mthd
  end

  def setup
    $collector ||= NewRelic::FakeCollector.new
    $collector.reset
    txn_rule_specs = [ { 'match_expression' => 'TransactionNameRuleTest',
                         'replacement' => 'Class' } ]
    metric_rule_specs = [ { 'match_expression' => 'TransactionNameRuleTest',
                            'replacement' => 'Class' } ]
    $collector.mock['connect'] = [200, {'return_value' => {
                                      "agent_run_id" => 666,
                            'transaction_name_rules' => txn_rule_specs,
                                 'metric_name_rules' => metric_rule_specs
                                    }}]
    $collector.run

    NewRelic::Agent.manual_start(:sync_startup => true,
                                 :force_reconnect => true)
    TestWidget.new.txn
  end

  def teardown
    NewRelic::Agent.shutdown
  end

  def test_transaction_name_rules
    metric_names = ::NewRelic::Agent.instance.stats_engine.metrics #.map{|k| k.name}
    assert(metric_names.include?('Controller/Class::TestWidget/txn'),
           "'Controller/Class::TestWidget/txn' not found in #{metric_names}")
    assert(metric_names.include?('Apdex/Class::TestWidget/txn'),
           "'Apdex/Class::TestWidget/txn' not found in #{metric_names}")
    assert(!metric_names.include?('Controller/TransactionNameRuleTest::TestWidget/txn'),
           "'Controller/TransactionNameRuleTest::TestWidget/txn' should not be in #{metric_names}")
  end

  def test_metric_name_rules
    NewRelic::Agent.instance.send(:harvest_and_send_timeslice_data)
    metric_names = $collector.calls_for('metric_data')[0].body[3].map{|m| m[0]['name']}
    assert(metric_names.include?('Custom/Class::TestWidget/mthd'),
           "'Custom/Class::TestWidget/mthd' not found in #{metric_names}")
    assert(!metric_names.include?('Custom/TransactionNameRuleTest::TestWidget/mthd'),
           "'Custom/TransactionNameRuleTest::TestWidget/mthd' should not be in #{metric_names}")
  end
end
