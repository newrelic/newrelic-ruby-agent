# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class NewRelic::Agent::TransactionInfoTest < Test::Unit::TestCase
  def test_has_correct_apdex_t_for_tansaction
    txn_info = NewRelic::Agent::TransactionInfo.get
    config = { :web_transactions_apdex => {'Controller/foo/bar' => 1.5},
      :apdex_t => 2.0 }

    with_config(config, :do_not_cast => true) do
      NewRelic::Agent::TransactionState.get.request_transaction = stub(:name => 'Controller/foo/bar')
      assert_equal 1.5, txn_info.apdex_t
      NewRelic::Agent::TransactionState.get.request_transaction = stub(:name => 'Controller/some/other')
      assert_equal 2.0, txn_info.apdex_t
    end
  end

  def test_has_correct_transaction_trace_threshold_when_default
    txn_info = NewRelic::Agent::TransactionInfo.get
    config = { :web_transactions_apdex => {'Controller/foo/bar' => 1.5},
      :apdex_t => 2.0 }

    with_config(config, :do_not_cast => true) do
      NewRelic::Agent::TransactionState.get.request_transaction = stub(:name => 'Controller/foo/bar')
      assert_equal 6.0, txn_info.transaction_trace_threshold
      NewRelic::Agent::TransactionState.get.request_transaction = stub(:name => 'Controller/some/other')
      assert_equal 8.0, txn_info.transaction_trace_threshold
    end
  end

  def test_has_correct_transaction_trace_threshold_when_specified
    txn_info = NewRelic::Agent::TransactionInfo.get
    config = {
      :web_transactions_apdex => {'Controller/foo/bar' => 1.5},
      :apdex_t => 2.0,
      :'transaction_tracer.transaction_threshold' => 4.0
    }

    with_config(config, :do_not_cast => true) do
      NewRelic::Agent::TransactionState.get.request_transaction = stub(:name => 'Controller/foo/bar')
      assert_equal 4.0, txn_info.transaction_trace_threshold
      NewRelic::Agent::TransactionState.get.request_transaction = stub(:name => 'Controller/some/other')
      assert_equal 4.0, txn_info.transaction_trace_threshold
    end
  end
end
