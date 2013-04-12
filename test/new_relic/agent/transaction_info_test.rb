# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'ostruct'

class NewRelic::Agent::TransactionInfoTest < Test::Unit::TestCase
  def setup
    @request = OpenStruct.new(:cookies => {'NRAGENT' => 'tk=12345678'})
    @request_with_embedded_tag = OpenStruct.new(:cookies => {'NRAGENT' => 'tk=1234<tag>evil</tag>5678'})
    @request_with_embedded_utf8_encoded_js = OpenStruct.new(:cookies => {'NRAGENT' => "tk=1234&#34&#93&#41&#595678"})
    @request_with_double_quotes = OpenStruct.new(:cookies => {'NRAGENT' => 'tk="""deadbeef"""'})
    @request_with_single_quotes = OpenStruct.new(:cookies => {'NRAGENT' => "tk='''deadbeef'''"})
    @request_with_multi_lt = OpenStruct.new(:cookies => {'NRAGENT' => 'tk=<<<deadbeef'})
    @request_with_multi_gt = OpenStruct.new(:cookies => {'NRAGENT' => 'tk=>>>deadbeef'})
    @request_with_bare_token = OpenStruct.new(:cookies => {'NRAGENT' => 0xdeadbeef})
    @request_with_nil_token = OpenStruct.new(:cookies => {'NRAGENT' => nil})
  end

  def test_get_token_safe_token_returned_untouched
    assert_equal("12345678", NewRelic::Agent::TransactionInfo.get_token(@request))
  end

  def test_get_token_with_embedded_tags_sanitized
    assert_equal("",NewRelic::Agent::TransactionInfo.get_token(@request_with_embedded_tag))
  end

  def test_get_token_with_embedded_utf8_js_sanitized
    assert_equal("1234&amp;#34&amp;#93&amp;#41&amp;#595678",
                 NewRelic::Agent::TransactionInfo.get_token(@request_with_embedded_utf8_encoded_js))
  end

  def test_get_token_replaces_double_quoted_token_with_empty_string
    assert_equal("", NewRelic::Agent::TransactionInfo.get_token(@request_with_double_quotes))
  end

  def test_get_token_replaces_single_quoted_toket_with_empty_string
    assert_equal("", NewRelic::Agent::TransactionInfo.get_token(@request_with_single_quotes))
  end

  def test_get_token_replaces_token_started_with_multiple_Lt_with_empty_string
    assert_equal("", NewRelic::Agent::TransactionInfo.get_token(@request_with_multi_lt))
  end

  def test_get_token_replaces_token_started_with_multiple_gt_with_empty_string
    assert_equal("", NewRelic::Agent::TransactionInfo.get_token(@request_with_multi_gt))
  end

  def test_get_token_bare_value_replaced_with_nil
    assert_equal(nil,NewRelic::Agent::TransactionInfo.get_token(@request_with_bare_token))
  end

  def test_get_token_nil_token_returns_nil_token
    assert_equal(nil,NewRelic::Agent::TransactionInfo.get_token(@request_with_ni_token))
  end

  def test_has_correct_apdex_t_for_tansaction
    txn_info = NewRelic::Agent::TransactionInfo.get
    config = { :web_transactions_apdex => {'Controller/foo/bar' => 1.5},
      :apdex_t => 2.0 }

    with_config(config, :do_not_cast => true) do
      txn_info.transaction = stub(:name => 'Controller/foo/bar')
      assert_equal 1.5, txn_info.apdex_t
      txn_info.transaction = stub(:name => 'Controller/some/other')
      assert_equal 2.0, txn_info.apdex_t
    end
  end

  def test_has_correct_transaction_trace_threshold_when_default
    txn_info = NewRelic::Agent::TransactionInfo.get
    config = { :web_transactions_apdex => {'Controller/foo/bar' => 1.5},
      :apdex_t => 2.0 }

    with_config(config, :do_not_cast => true) do
      txn_info.transaction = stub(:name => 'Controller/foo/bar')
      assert_equal 6.0, txn_info.transaction_trace_threshold
      txn_info.transaction = stub(:name => 'Controller/some/other')
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
      txn_info.transaction = stub(:name => 'Controller/foo/bar')
      assert_equal 4.0, txn_info.transaction_trace_threshold
      txn_info.transaction = stub(:name => 'Controller/some/other')
      assert_equal 4.0, txn_info.transaction_trace_threshold
    end
  end
end
