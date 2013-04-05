# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class SetTransactionNameTest < Test::Unit::TestCase
  include NewRelic::Agent::MethodTracer

  class TestTransactor
    include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation
    def parent_txn
      NewRelic::Agent.set_transaction_name('Controller/TestTransactor/parent')
      yield if block_given?
      child_txn
    end
    add_transaction_tracer :parent_txn

    def child_txn
      NewRelic::Agent.set_transaction_name('OtherTransaction/Background/TestTransactor/child')
    end
    add_transaction_tracer :child_txn
  end

  def setup
    NewRelic::Agent.manual_start
    @transactor = TestTransactor.new
    @stats_engine = NewRelic::Agent.instance.stats_engine
  end

  def teardown
    NewRelic::Agent.shutdown
  end

  def test_apply_to_metric_names
    @transactor.parent_txn
    [ 'Controller/TestTransactor/parent',
      'OtherTransaction/Background/TestTransactor/child',
      [ 'OtherTransaction/Background/TestTransactor/child',
        'Controller/TestTransactor/parent'],
      'Apdex/TestTransactor/parent' ].each do |metric|
      assert(@stats_engine.lookup_stats(*metric),
             "Expected to find #{metric} in stats hash #{NewRelic::Agent.instance.stats_engine.instance_variable_get(:@stats_hash)}")
    end
  end

  def test_apply_to_metric_scopes
    @transactor.parent_txn do
      trace_execution_scoped('Custom/something') {}
    end
    assert @stats_engine.lookup_stats('Custom/something',
                                      'Controller/TestTransactor/parent')
  end

  def test_apply_to_traced_transactions
    @transactor.parent_txn
    assert_equal('Controller/TestTransactor/parent',
                 NewRelic::Agent.instance.transaction_sampler.last_sample \
                   .params[:path])
  end

  def _test_apply_to_traced_errors
    @transactor.parent_txn do
      NewRelic::Agent.notice_error(RuntimeError.new('toot'))
    end
    assert_equal('Controller/TestTransactor/parent',
                 NewRelic::Agent.instance.error_collector.errors.last.path)
  end

  def _test_set_name_is_subject_to_txn_name_rules
    rule = NewRelic::Agent::RulesEngine::Rule.new('match_expression' => 'parent',
                                                  'replacement'      => 'dad')
    NewRelic::Agent.instance.transaction_rules << rule
    @transactor.parent_txn
    assert @stats_engine.lookup_stats('Custom/TestTransactor/dad')
  end

  def _test_does_not_overwrite_name_when_set_by_CAT
  end

  def _test_does_not_overwrite_name_when_set_by_RUM
  end
end
