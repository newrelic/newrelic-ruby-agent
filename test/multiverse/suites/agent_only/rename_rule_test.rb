# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class RenameRuleTest < Minitest::Test

  include MultiverseHelpers

  setup_and_teardown_agent do |collector|
    rules = [
      { 'match_expression' => 'RenameRuleTest', 'replacement' => 'Class' },
      { 'match_expression' => 'Nothing',        'replacement' => 'Something' }
    ]
    segment_terms_rules = [
      { 'prefix' => 'other/qux', 'terms' => ['Nothing', 'one', 'two'] }
    ]
    collector.stub('connect', {
      'agent_run_id'              => 666,
      'transaction_name_rules'    => rules,
      'metric_name_rules'         => rules,
      'transaction_segment_terms' => segment_terms_rules
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

    assert_metrics_recorded([
      'Controller/Class::TestWidget/txn',
      'Apdex/Class::TestWidget/txn'
    ])

    refute_metrics_recorded('Controller/RenameRuleTest::TestWidget/txn')
  end

  def test_metric_name_rules
    TestWidget.new.txn

    NewRelic::Agent.instance.send(:harvest_and_send_timeslice_data)
    metric_names = $collector.calls_for('metric_data').first.metric_names

    assert_includes(metric_names, 'Custom/Class::TestWidget/mthd')

    assert_not_includes(metric_names, 'Custom/RenameRuleTest::TestWidget/mthd')
  end

  def test_transaction_segment_terms_do_not_apply_to_metrics
    in_transaction do
      NewRelic::Agent.record_metric("other/qux/foo/bar", 42)
    end

    assert_metrics_recorded(['other/qux/foo/bar'])
  end

  def test_transaction_segment_terms_do_apply_to_transaction_names
    in_transaction do
      NewRelic::Agent.set_transaction_name('qux/one/two/three/four')
    end

    assert_metrics_recorded(['other/qux/one/two/*'])
    assert_metrics_not_recorded(['other/qux/one/two/three/four'])
  end

  def test_transaction_segment_terms_applied_after_other_rules
    in_transaction do
      NewRelic::Agent.set_transaction_name('qux/Nothing/one/two/three')
    end

    assert_metrics_recorded(['other/qux/*/one/two/*'])
    assert_metrics_not_recorded([
      'other/qux/Something/one/two/*',
      'other/qux/Something/one/two/three',
      'other/qux/Nothing/one/two/*',
      'other/qux/Nothing/one/two/three'
    ])
  end
end
