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

end
