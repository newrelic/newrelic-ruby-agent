# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/commands/xray_session'

module NewRelic::Agent::Commands
  class XraySessionTest < Test::Unit::TestCase

    def target_for_shared_client_tests
      XraySession.new('run_profiler' => true)
    end

    def test_foo
      assert true
    end
  end
end
