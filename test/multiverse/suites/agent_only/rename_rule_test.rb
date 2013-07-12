# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'multiverse_helpers'

class RenameRuleTest < MiniTest::Unit::TestCase

  include MultiverseHelpers

  setup_and_teardown_agent do |collector|
    rules = [ { 'match_expression' => 'RenameRuleTest', 'replacement' => 'Class' } ]
    collector.stub('connect', {
      'agent_run_id'           => 666,
      'transaction_name_rules' => rules,
      'metric_name_rules'      => rules
    })
  end

  class TestWidget
    include NewRelic::Agent::Instrumentation::ControllerInstrumentation

    def txn
      mthd
    end
    add_transaction_tracer :txn

    def mthd
      'doot de doo'
    end
    add_method_tracer :mthd
  end

  def test_transaction_names_rules
    TestWidget.new.txn

    metric_names = NewRelic::Agent.instance.stats_engine.metrics

    assert_includes(metric_names, 'Controller/Class::TestWidget/txn')
    assert_includes(metric_names, 'Apdex/Class::TestWidget/txn')

    assert_not_includes(metric_names, 'Controller/RenameRuleTest::TestWidget/txn')
  end

  def test_metric_name_rules
    TestWidget.new.txn

    NewRelic::Agent.instance.send(:harvest_and_send_timeslice_data)
    metric_names = $collector.calls_for('metric_data').first.metric_names

    assert_includes(metric_names, 'Custom/Class::TestWidget/mthd')

    assert_not_includes(metric_names, 'Custom/RenameRuleTest::TestWidget/mthd')
  end

end
