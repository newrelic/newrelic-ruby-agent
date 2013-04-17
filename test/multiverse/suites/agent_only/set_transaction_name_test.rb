# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class SetTransactionNameTest < Test::Unit::TestCase
  include NewRelic::Agent::MethodTracer

  class TestTransactor
    include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation
    def parent_txn
      NewRelic::Agent.set_transaction_name('TestTransactor/parent')
      yield if block_given?
      child_txn
    end
    add_transaction_tracer :parent_txn

    def child_txn
      NewRelic::Agent.set_transaction_name('TestTransactor/child', :category => :task)
    end
    add_transaction_tracer :child_txn

    newrelic_ignore :only => :ignored_txn
    def ignored_txn
      NewRelic::Agent.set_transaction_name('Ignore/me')
    end
  end

  def setup
    NewRelic::Agent.manual_start(:browser_key => 'browserKey', :application_id => 'appId',
                                 :beacon => 'beacon', :episodes_file => 'this_is_my_file')
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

  def test_apply_to_traced_errors
    @transactor.parent_txn do
      NewRelic::Agent.notice_error(RuntimeError.new('toot'))
    end
    assert_equal('Controller/TestTransactor/parent',
                 NewRelic::Agent.instance.error_collector.errors.last.path)
  end

  def test_set_name_is_subject_to_txn_name_rules
    rule = NewRelic::Agent::RulesEngine::Rule.new('match_expression' => 'parent',
                                                  'replacement'      => 'dad')
    NewRelic::Agent.instance.transaction_rules << rule
    @transactor.parent_txn
    assert @stats_engine.lookup_stats('Controller/TestTransactor/dad')
  end

  def test_does_not_overwrite_name_when_set_by_RUM
    @transactor.parent_txn do
      NewRelic::Agent.browser_timing_header
      NewRelic::Agent.browser_timing_footer
      NewRelic::Agent.set_transaction_name('this/should/not/work')
    end
    assert_nil @stats_engine.lookup_stats('Controller/this/should/not/work')
    assert @stats_engine.lookup_stats('Controller/TestTransactor/parent')
  end

  def test_ignoring_action
    @transactor.ignored_txn
    assert_nil @stats_engine.lookup_stats('Controller/Ignore/me')
  end
end
