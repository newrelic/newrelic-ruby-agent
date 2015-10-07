# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class SetTransactionNameTest < Minitest::Test
  include NewRelic::Agent::MethodTracer

  include MultiverseHelpers

  setup_and_teardown_agent(:application_id => 'appId',
                           :beacon => 'beacon',
                           :browser_key => 'browserKey',
                           :js_agent_loader => 'loader')

  class TestTransactor
    include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation

    def parent_txn(child_category=nil)
      NewRelic::Agent.set_transaction_name('TestTransactor/parent')
      yield if block_given?
      child_txn(child_category)
    end

    add_transaction_tracer :parent_txn

    def child_txn(category)
      opts = {}
      opts[:category] = category if category
      NewRelic::Agent.set_transaction_name('TestTransactor/child', opts)
    end

    add_transaction_tracer :child_txn

    newrelic_ignore :only => :ignored_txn

    def ignored_txn
      NewRelic::Agent.set_transaction_name('Ignore/me')
    end
  end

  def test_metric_names_when_child_has_different_category
    TestTransactor.new.parent_txn(:task)

    assert_metrics_recorded([
      'Controller/TestTransactor/parent',
      'Nested/OtherTransaction/Background/TestTransactor/child',
      ['Nested/OtherTransaction/Background/TestTransactor/child', 'Controller/TestTransactor/parent'],
      'Apdex/TestTransactor/parent'])
  end

  def test_apply_to_metric_names
    TestTransactor.new.parent_txn

    assert_metrics_recorded([
      'Controller/TestTransactor/child',
      'Nested/Controller/TestTransactor/child',
      'Nested/Controller/TestTransactor/parent',
      ['Nested/Controller/TestTransactor/child',
        'Controller/TestTransactor/child'],
      ['Nested/Controller/TestTransactor/parent',
        'Controller/TestTransactor/child'],
      'Apdex/TestTransactor/child'])
  end

  def test_apply_to_metric_scopes
    TestTransactor.new.parent_txn do
      trace_execution_scoped('Custom/something') {}
    end
    assert_metrics_recorded(['Custom/something',
                             'Controller/TestTransactor/child'])
  end

  def test_apply_to_traced_transactions
    TestTransactor.new.parent_txn
    sample = NewRelic::Agent.instance.transaction_sampler.last_sample
    assert_equal('Controller/TestTransactor/child', sample.transaction_name)
  end

  def test_apply_to_traced_errors
    TestTransactor.new.parent_txn do
      NewRelic::Agent.notice_error(RuntimeError.new('toot'))
    end
    errors = harvest_error_traces!
    assert_equal('Controller/TestTransactor/child', errors.last.path)
  end

  def test_set_name_is_subject_to_txn_name_rules
    connect_response = {
      'agent_run_id' => 1,
      'transaction_name_rules' => [
        { 'match_expression' => 'child', 'replacement' => 'kid' }
      ]
    }

    $collector.stub('connect', connect_response)

    trigger_agent_reconnect

    TestTransactor.new.parent_txn
    assert_metrics_recorded(['Controller/TestTransactor/kid'])
  end

  def test_does_not_overwrite_name_when_set_by_RUM
    TestTransactor.new.parent_txn do
      # Transaction name is only frozen if RUM is actually injected
      refute_empty NewRelic::Agent.browser_timing_header

      NewRelic::Agent.set_transaction_name('this/should/not/work')
    end
    assert_metrics_not_recorded(['Controller/this/should/not/work'])
    assert_metrics_recorded(['Controller/TestTransactor/parent'])
  end

  def test_ignoring_action
    TestTransactor.new.ignored_txn
    assert_metrics_not_recorded(['Controller/Ignore/me'])
  end
end
