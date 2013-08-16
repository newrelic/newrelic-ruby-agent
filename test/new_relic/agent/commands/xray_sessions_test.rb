# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/commands/xray_sessions'

module NewRelic::Agent::Commands
  class XraySessionsTest < Test::Unit::TestCase

    attr_reader :sessions, :service

    FIRST_SESSION_ID = 123
    SECOND_SESSION_ID = 42

    FIRST_SESSION_META  = {"x_ray_id" => FIRST_SESSION_ID}
    SECOND_SESSION_META = {"x_ray_id" => SECOND_SESSION_ID}

    def setup
      @service  = stub
      @sessions = NewRelic::Agent::Commands::XraySessions.new(@service)
    end

    def test_handles_active_xray_sessions_command_creates_a_session
      stub_metadata_for(FIRST_SESSION_ID)

      handle_command_for(FIRST_SESSION_ID)

      assert sessions.include?(FIRST_SESSION_ID)

      session = sessions[FIRST_SESSION_ID]
      assert_equal FIRST_SESSION_ID, session.id
      assert_equal true, session.active?
    end

    def test_can_add_multiple_sessions
      stub_metadata_for(FIRST_SESSION_ID, SECOND_SESSION_ID)

      handle_command_for(FIRST_SESSION_ID, SECOND_SESSION_ID)

      assert sessions.include?(FIRST_SESSION_ID)
      assert sessions.include?(SECOND_SESSION_ID)
    end

    def test_doesnt_recall_metadata_for_already_active_sessions
      stub_metadata_for(FIRST_SESSION_ID)
      stub_metadata_for(SECOND_SESSION_ID)

      handle_command_for(FIRST_SESSION_ID)
      handle_command_for(FIRST_SESSION_ID, SECOND_SESSION_ID)

      assert sessions.include?(FIRST_SESSION_ID)
      assert sessions.include?(SECOND_SESSION_ID)
    end

    def test_adding_doesnt_replace_session_object
      stub_metadata_for(FIRST_SESSION_ID)

      handle_command_for(FIRST_SESSION_ID)
      expected = sessions[FIRST_SESSION_ID]

      handle_command_for(FIRST_SESSION_ID)
      result = sessions[FIRST_SESSION_ID]

      assert_equal expected, result
    end

    def test_can_access_session
      stub_metadata_for(FIRST_SESSION_ID)

      handle_command_for(FIRST_SESSION_ID)

      session = sessions[FIRST_SESSION_ID]
      assert_equal FIRST_SESSION_ID, session.id
    end

    def test_adding_a_session_actives_it
      stub_metadata_for(FIRST_SESSION_ID)

      handle_command_for(FIRST_SESSION_ID)

      session = sessions[FIRST_SESSION_ID]
      assert_equal true, session.active?
    end

    def test_removes_inactive_sessions
      stub_metadata_for(FIRST_SESSION_ID, SECOND_SESSION_ID)
      stub_metadata_for(FIRST_SESSION_ID)

      handle_command_for(FIRST_SESSION_ID, SECOND_SESSION_ID)
      handle_command_for(FIRST_SESSION_ID)

      assert_equal true, sessions.include?(FIRST_SESSION_ID)
      assert_equal false, sessions.include?(SECOND_SESSION_ID)
    end

    def test_removing_inactive_sessions_deactivates_them
      stub_metadata_for(FIRST_SESSION_ID)

      handle_command_for(FIRST_SESSION_ID)
      session = sessions[FIRST_SESSION_ID]

      handle_command_for(*[])

      assert_equal false, session.active?
    end


    # Helpers

    def handle_command_for(*session_ids)
      command = command_for(*session_ids)
      sessions.handle_active_xray_sessions(command)
    end

    def command_for(*session_ids)
      command = create_agent_command({ "xray_ids" => session_ids})
    end

    def stub_metadata_for(*session_ids)
      case
      when session_ids == [FIRST_SESSION_ID]
        result = [FIRST_SESSION_META]
      when session_ids == [SECOND_SESSION_ID]
        result = [SECOND_SESSION_META]
      when session_ids == [FIRST_SESSION_ID, SECOND_SESSION_ID]
        result = [FIRST_SESSION_META, SECOND_SESSION_META]
      else
        raise "Unrecognized session ids for stubbing... sorry"
      end

      @service.stubs(:get_xray_metadata).with(session_ids).returns(result)
    end

  end
end
