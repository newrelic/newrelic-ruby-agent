# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'resolv'
require 'mocha/setup'

class LoadTest < Minitest::Test
  def test_loading_agent_when_disabled_does_not_resolv_addresses
    ::Resolv.expects(:getaddress).never
    ::IPSocket.expects(:getaddress).never

    require File.expand_path(File.join(File.dirname(__FILE__),'..','test_helper'))
  end
end
