# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/commands/xray_sessions'

module NewRelic::Agent::Commands
  class XraySessionsTest < Test::Unit::TestCase

    attr_reader :sessions, :service

    FIRST_ID = 123
    FIRST_NAME = "Next Session"
    FIRST_TRANSACTION_NAME = "Controller/blogs/index"
    FIRST_REQUESTED_TRACE_COUNT = 10
    FIRST_DURATION = 600
    FIRST_SAMPLE_PERIOD = 0.2
    FIRST_RUN_PROFILER = false

    FIRST_METADATA  = {
      "x_ray_id"              => FIRST_ID,
      "xray_session_name"     => FIRST_NAME,
      "key_transaction_name"  => FIRST_TRANSACTION_NAME,
      "requested_trace_count" => FIRST_REQUESTED_TRACE_COUNT,
      "duration"              => FIRST_DURATION,
      "sample_period"         => FIRST_SAMPLE_PERIOD,
      "run_profiler"          => FIRST_RUN_PROFILER,
    }

    SECOND_ID = 42
    SECOND_METADATA = {"x_ray_id" => SECOND_ID}

    def setup
      @service  = stub
      @sessions = NewRelic::Agent::Commands::XraySessions.new(@service)

      @service.stubs(:get_xray_metadata).with([FIRST_ID]).returns([FIRST_METADATA])
      @service.stubs(:get_xray_metadata).with([SECOND_ID]).returns([SECOND_METADATA])
      @service.stubs(:get_xray_metadata).with([FIRST_ID, SECOND_ID]).returns([FIRST_METADATA, SECOND_METADATA])
    end

    def test_can_add_sessions
      handle_command_for(FIRST_ID, SECOND_ID)

      assert sessions.include?(FIRST_ID)
      assert sessions.include?(SECOND_ID)
    end

    def test_creates_a_session_from_collector_metadata
      handle_command_for(FIRST_ID)

      session = sessions[FIRST_ID]
      assert_equal FIRST_ID, session.id
      assert_equal FIRST_NAME, session.xray_session_name
      assert_equal FIRST_REQUESTED_TRACE_COUNT, session.requested_trace_count
      assert_equal FIRST_DURATION, session.duration
      assert_equal FIRST_SAMPLE_PERIOD, session.sample_period
      assert_equal FIRST_RUN_PROFILER, session.run_profiler
      assert_equal FIRST_TRANSACTION_NAME, session.key_transaction_name
      assert_equal true, session.active?
    end

    def test_defaults_out_properties_for_session_missing_metadata
      handle_command_for(SECOND_ID)

      session = sessions[SECOND_ID]
      assert_not_nil session.xray_session_name
      assert_not_nil session.requested_trace_count
      assert_not_nil session.duration
      assert_not_nil session.sample_period
      assert_not_nil session.run_profiler
      assert_not_nil session.key_transaction_name
      assert_not_nil session.active?
    end

    def test_doesnt_recall_metadata_for_already_active_sessions
      # unstub fails on certain mocha/rails versions (rails23 env)
      # replace the service instead to let us expect to never get the call...
      @service = stub
      @sessions.send(:service=, @service)

      @service.stubs(:get_xray_metadata).with([FIRST_ID]).returns([FIRST_METADATA])
      @service.stubs(:get_xray_metadata).with([SECOND_ID]).returns([SECOND_METADATA])

      @service.expects(:get_xray_metadata).with([FIRST_ID, SECOND_ID]).never

      handle_command_for(FIRST_ID)
      handle_command_for(FIRST_ID, SECOND_ID)

      assert sessions.include?(FIRST_ID)
      assert sessions.include?(SECOND_ID)
    end

    def test_adding_doesnt_replace_session_object

      handle_command_for(FIRST_ID)
      expected = sessions[FIRST_ID]

      handle_command_for(FIRST_ID)
      result = sessions[FIRST_ID]

      assert_equal expected, result
    end

    def test_can_access_session

      handle_command_for(FIRST_ID)

      session = sessions[FIRST_ID]
      assert_equal FIRST_ID, session.id
    end

    def test_can_find_session_id_by_transaction_name
      handle_command_for(FIRST_ID)

      result = sessions.session_id_for_transaction_name(FIRST_TRANSACTION_NAME)
      assert_equal(FIRST_ID, result)
    end

    def test_can_find_session_id_by_missing_transaction_name
      result = sessions.session_id_for_transaction_name("MISSING")
      assert_nil result
    end

    def test_adding_a_session_actives_it

      handle_command_for(FIRST_ID)

      session = sessions[FIRST_ID]
      assert_equal true, session.active?
    end

    def test_removes_inactive_sessions

      handle_command_for(FIRST_ID, SECOND_ID)
      handle_command_for(FIRST_ID)

      assert_equal true, sessions.include?(FIRST_ID)
      assert_equal false, sessions.include?(SECOND_ID)
    end

    def test_removing_inactive_sessions_deactivates_them

      handle_command_for(FIRST_ID)
      session = sessions[FIRST_ID]

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

  end
end
