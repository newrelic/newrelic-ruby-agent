# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/hostname'

module NewRelic
  module Agent
    class HostnameTest < MiniTest::Unit::TestCase
      def test_get_returns_socket_hostname
        Socket.stubs(:gethostname).returns('Rivendell')
        assert_equal 'Rivendell', NewRelic::Agent::Hostname.get
      end
    end
  end
end
