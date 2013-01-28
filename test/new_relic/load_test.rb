# require File.expand_path(File.join(File.dirname(__FILE__),'..','test_helper'))
require 'test/unit'
require 'resolv'
require 'mocha'

class LoadTest < Test::Unit::TestCase
  def test_loading_agent_when_disabled_does_not_resolv_addresses
    ::Resolv.expects(:getaddress).never
    ::IPSocket.expects(:getaddress).never

    require File.expand_path(File.join(File.dirname(__FILE__),'..','test_helper'))
  end
end
