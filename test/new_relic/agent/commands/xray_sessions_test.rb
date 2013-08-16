# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/commands/xray_sessions'

module NewRelic::Agent::Commands
  class XraySessionsTest < Test::Unit::TestCase

    attr_reader :sessions

    FIRST_SESSION_ID = 123
    SECOND_SESSION_ID = 42

    FIRST_SESSION_META  = {"xray_id" => FIRST_SESSION_ID}
    SECOND_SESSION_META = {"xray_id" => SECOND_SESSION_ID}

    def setup
      @sessions = NewRelic::Agent::Commands::XraySessions.new
    end

    def test_can_add_a_session_from_metadata
      sessions.active_sessions([FIRST_SESSION_META])
      assert sessions.include?(FIRST_SESSION_ID)
    end

    def test_can_add_multiple_sessions
      sessions.active_sessions([FIRST_SESSION_META, SECOND_SESSION_META])
      assert sessions.include?(FIRST_SESSION_ID)
      assert sessions.include?(SECOND_SESSION_ID)
    end

    def test_adding_doesnt_replace_session_object
      sessions.active_sessions([FIRST_SESSION_META])
      expected = sessions[FIRST_SESSION_ID]

      sessions.active_sessions([FIRST_SESSION_META])
      result = sessions[FIRST_SESSION_ID]

      assert_equal expected, result
    end

    def test_can_access_session
      sessions.active_sessions([FIRST_SESSION_META])

      session = sessions[FIRST_SESSION_ID]
      assert_equal FIRST_SESSION_ID, session.id
    end

    def test_adding_a_session_actives_it
      sessions.active_sessions([FIRST_SESSION_META])

      session = sessions[FIRST_SESSION_ID]
      assert_equal true, session.active?
    end

    def test_removes_inactive_sessions
      sessions.active_sessions([FIRST_SESSION_META, SECOND_SESSION_META])
      sessions.active_sessions([FIRST_SESSION_META])

      assert_equal true, sessions.include?(FIRST_SESSION_ID)
      assert_equal false, sessions.include?(SECOND_SESSION_ID)
    end

    def test_removing_inactive_sessions_deactivates_them
      sessions.active_sessions([FIRST_SESSION_META])
      session = sessions[FIRST_SESSION_ID]

      sessions.active_sessions([])

      assert_equal false, session.active?
    end
  end
end
