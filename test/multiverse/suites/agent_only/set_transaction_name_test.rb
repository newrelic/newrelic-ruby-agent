# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class SetTransactionNameTest < Test::Unit::TestCase
  class TestTransactor
    include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation
    def parent_txn
      NewRelic::Agent.set_transaction_name('Controller/TestTransactor/parent')
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
  end

  def teardown
    NewRelic::Agent.shutdown
  end

  def test_apply_to_metric_names
    TestTransactor.new.parent_txn
    [ 'Controller/TestTransactor/parent',
      'OtherTransaction/Background/TestTransactor/child',
      [ 'OtherTransaction/Background/TestTransactor/child',
        'Controller/TestTransactor/parent'],
      'Apdex/TestTransactor/parent' ].each do |metric|
      assert(NewRelic::Agent.instance.stats_engine \
               .lookup_stats(*metric),
             "Expected to find #{metric} in stats hash #{NewRelic::Agent.instance.stats_engine.instance_variable_get(:@stats_hash)}")
    end
  end

  def _test_apply_to_metric_scopes
  end

  def _test_apply_to_traced_transactions
  end

  def _test_apply_to_traced_errors
  end

  def _test_apply_to_traced_sql
  end

  def _test_does_not_overwrite_name_when_set_by_CAT
  end

  def _test_set_name_is_subject_to_txn_name_rules
  end
end
