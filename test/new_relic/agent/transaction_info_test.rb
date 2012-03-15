require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'ostruct'

class NewRelic::Agent::TransactionInfoTest < Test::Unit::TestCase
  def setup
    @request = OpenStruct.new(:cookies => {'NRAGENT' => 'tk=1234<tag>evil</tag>5678'})
  end
  
  def test_get_token_gets_sanitized_token_from_cookie
    assert_equal('1234&lt;tag&gt;evil&lt;/tag&gt;5678',
                 NewRelic::Agent::TransactionInfo.get_token(@request))
  end
end
