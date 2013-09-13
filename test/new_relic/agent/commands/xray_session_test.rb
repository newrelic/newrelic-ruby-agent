# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/commands/xray_session'

module NewRelic::Agent::Commands
  class XraySessionTest < Test::Unit::TestCase

    def test_creates_thread_profile_if_run_profiler_is_true
      session = XraySession.new('run_profiler' => true)
      assert session.thread_profile
    end

    def test_passes_xray_id_on_to_thread_profile
      session = XraySession.new(
        'x_ray_id' => 1234,
        'run_profiler' => true
      )
      assert_equal(1234, session.thread_profile.xray_id)
    end

    def test_does_not_create_thread_profile_if_run_profiler_is_false
      session = XraySession.new('run_profiler' => false)
      assert_nil(session.thread_profile)
    end
  end
end
