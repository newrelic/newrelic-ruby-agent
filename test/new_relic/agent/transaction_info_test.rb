require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'ostruct'

class NewRelic::Agent::TransactionInfoTest < Test::Unit::TestCase
  def setup
    @request = OpenStruct.new(:cookies => {'NRAGENT' => 'tk=1234<tag>evil</tag>5678'})
    @request_with_double_quotes = OpenStruct.new(:cookies => {'NRAGENT' => 'tk="""deadbeef"""'})
    @request_with_single_quotes = OpenStruct.new(:cookies => {'NRAGENT' => "tk='''deadbeef'''"})
    @request_with_multi_lt = OpenStruct.new(:cookies => {'NRAGENT' => 'tk=<<<deadbeef'})
    @request_with_multi_gt = OpenStruct.new(:cookies => {'NRAGENT' => 'tk=>>>deadbeef'}) 
  end
  
  def test_get_token_gets_sanitized_token_from_cookie
    assert_equal('1234&lt;tag&gt;evil&lt;/tag&gt;5678',
                 NewRelic::Agent::TransactionInfo.get_token(@request))
  end

  def test_get_token_replaces_double_quoted_token_with_empty_string
  	assert_equal("",NewRelic::Agent::TransactionInfo.get_token(@request_with_double_quotes))
  end

  def test_get_token_replaces_single_quoted_toket_with_empty_string
  	assert_equal("",NewRelic::Agent::TransactionInfo.get_token(@request_with_single_quotes))
  end

  def test_get_token_replaces_token_started_with_multiple_Lt_with_empty_string
  	assert_equal("",NewRelic::Agent::TransactionInfo.get_token(@request_with_multi_lt))
  end

  def test_get_token_replaces_token_started_with_multiple_gt_with_empty_string
  	assert_equal("",NewRelic::Agent::TransactionInfo.get_token(@request_with_multi_gt))
  end
end
