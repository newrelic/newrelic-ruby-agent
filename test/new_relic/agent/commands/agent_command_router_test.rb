# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/commands/agent_command_router'
require 'new_relic/agent/commands/xray_session'

class AgentCommandRouterTest < Test::Unit::TestCase

  DEFAULT_ARGS = {
    "profile_id" => 42
  }

  BAZZLE_ID = 123
  BAZZLE = [BAZZLE_ID,{
    "name" => "bazzle",
    "arguments" => DEFAULT_ARGS
  }]

  BOOM_ID = 666
  BOOM = [BOOM_ID,{
    "name" => "boom",
    "arguments" => DEFAULT_ARGS
  }]

  UNRECOGNIZED_ID = 42
  UNRECOGNIZED = [UNRECOGNIZED_ID, {
    "name" => "JIBBERISH",
    "arguments" => {}
  }]

  attr_reader :service, :agent_commands, :calls

  def setup
    @service = stub
    NewRelic::Agent.agent.stubs(:service).returns(@service)
    @calls = []

    @agent_commands = NewRelic::Agent::Commands::AgentCommandRouter.new
    @agent_commands.handlers["bazzle"] = Proc.new { |args| handle_bazzle_command(args) }
    @agent_commands.handlers["boom"]   = Proc.new { |args| handle_boom_command(args) }
  end

  def teardown
    agent_commands.backtrace_service.worker_thread.join if agent_commands.backtrace_service.worker_thread
  end

  # General command routing

  def test_check_for_and_handle_agent_commands_dispatches_command
    service.stubs(:get_agent_commands).returns([BAZZLE])
    service.stubs(:agent_command_results)

    agent_commands.check_for_and_handle_agent_commands

    assert_equal [DEFAULT_ARGS], calls
  end

  def test_check_for_and_handle_agent_commands_generates_results
    service.stubs(:get_agent_commands).returns([BAZZLE])
    service.expects(:agent_command_results).with({ BAZZLE_ID.to_s => {} })

    agent_commands.check_for_and_handle_agent_commands
  end

  def test_check_for_and_handle_agent_commands_dispatches_with_error
    service.stubs(:get_agent_commands).returns([BOOM])
    service.expects(:agent_command_results).with({ BOOM_ID.to_s => { "error" => "BOOOOOM" }})

    agent_commands.check_for_and_handle_agent_commands
  end

  def test_check_for_and_handle_agent_commands_allows_multiple
    service.stubs(:get_agent_commands).returns([BAZZLE, BOOM])
    service.expects(:agent_command_results).with({ BAZZLE_ID.to_s => {},
                                                   BOOM_ID.to_s => { "error" => "BOOOOOM" }})
    agent_commands.check_for_and_handle_agent_commands
  end

  def test_check_for_and_handle_agent_commands_doesnt_call_results_if_no_commands
    service.stubs(:get_agent_commands).returns([])
    service.expects(:agent_command_results).never

    agent_commands.check_for_and_handle_agent_commands
  end

  def test_unrecognized_commands
    service.stubs(:get_agent_commands).returns([UNRECOGNIZED])
    service.stubs(:agent_command_results)

    expects_logging(:debug, regexp_matches(/unrecognized/i))

    agent_commands.check_for_and_handle_agent_commands
  end

  # Start/stop X-Ray tests

  def test_empty_agent_commands_stops_running_xray
    start_xray_session(123)

    service.stubs(:get_agent_commands).returns([])
    agent_commands.check_for_and_handle_agent_commands

    assert_false agent_commands.xray_session_collection.include?(123)
  end

  # Harvesting tests

  if NewRelic::Agent::Threading::BacktraceService.is_supported?

    DISCONNECTING = true
    NOT_DISCONNECTING = false

    def test_harvest_data_to_send_not_started
      result = agent_commands.harvest_data_to_send(NOT_DISCONNECTING)
      assert_equal({}, result)
    end

    def test_harvest_data_to_send_with_profile_in_progress
      start_profile('duration' => 1.0)

      result = agent_commands.harvest_data_to_send(NOT_DISCONNECTING)
      assert_equal({}, result)
    end

    def test_harvest_data_to_send_with_profile_completed
      start_profile('duration' => 1.0)

      advance_time(1.1)
      result = agent_commands.harvest_data_to_send(NOT_DISCONNECTING)

      assert_not_nil result[:profile_data]
    end

    def test_can_stop_multiple_times_safely
      start_profile('duration' => 1.0)

      advance_time(1.1)
      agent_commands.thread_profiler_session.stop(true)

      result = agent_commands.harvest_data_to_send(NOT_DISCONNECTING)
      assert_not_nil result[:profile_data]
    end

    def test_transmits_after_forced_stop
      start_profile('duration' => 1.0)

      agent_commands.thread_profiler_session.stop(true)

      result = agent_commands.harvest_data_to_send(NOT_DISCONNECTING)
      assert_not_nil result[:profile_data]
    end

    def test_harvest_data_to_send_with_no_profile_disconnecting
      result = agent_commands.harvest_data_to_send(DISCONNECTING)
      assert_nil result[:profile_data]
    end

    def test_harvest_data_to_send_with_profile_in_progress_but_disconnecting
      start_profile('duration' => 1.0)

      result = agent_commands.harvest_data_to_send(DISCONNECTING)
      assert_not_nil result[:profile_data]
    end

    def test_harvest_data_to_send_with_xray_sessions_in_progress
      start_xray_session(123)
      start_xray_session(456)

      sample_on_profiles

      result = agent_commands.harvest_data_to_send(NOT_DISCONNECTING)

      assert_equal 2, result[:profile_data].length
    end

    def test_harvest_data_to_send_with_xray_sessions_and_thread_profile_in_progress
      start_xray_session(123)
      start_xray_session(456)

      start_profile('duration' => 1.0)

      sample_on_profiles

      result = agent_commands.harvest_data_to_send(NOT_DISCONNECTING)

      assert_equal 2, result[:profile_data].length
    end

    def test_harvest_data_to_send_with_xray_sessions_and_completed_thread_profile
      start_xray_session(123)
      start_xray_session(456)

      start_profile('duration' => 1.0)

      sample_on_profiles
      advance_time(1.1)

      result = agent_commands.harvest_data_to_send(NOT_DISCONNECTING)

      assert_equal 3, result[:profile_data].length
    end

  end

  # Helpers

  def handle_bazzle_command(command)
    calls << command.arguments
  end

  def handle_boom_command(command)
    raise NewRelic::Agent::Commands::AgentCommandRouter::AgentCommandError.new("BOOOOOM")
  end

  def start_profile(args={})
    freeze_time
    agent_commands.backtrace_service.worker_loop.stubs(:run)
    agent_commands.thread_profiler_session.start(create_agent_command(args))
  end

  def start_xray_session(id)
    args = { 'x_ray_id' => id, 'key_transaction_name' => "txn_#{id}" }
    session = NewRelic::Agent::Commands::XraySession.new(args)

    agent_commands.backtrace_service.worker_loop.stubs(:run)
    agent_commands.xray_session_collection.add_session(session)
  end

  def sample_on_profiles
    agent_commands.backtrace_service.profiles.each do |(_, profile)|
      profile.aggregate([], :request, Thread.current)
    end
  end

end
