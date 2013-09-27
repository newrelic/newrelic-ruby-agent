# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/commands/xray_session'

module NewRelic::Agent::Commands
  class XraySessionTest < Test::Unit::TestCase

    def test_run_profiler
      session = XraySession.new('run_profiler' => true)
      assert session.run_profiler?
    end

    def test_run_profiler_respects_config
      with_config(:'xray_session.allow_profiles' => false) do
        session = XraySession.new('run_profiler' => true)
        assert_false session.run_profiler?
      end
    end

  end
end
