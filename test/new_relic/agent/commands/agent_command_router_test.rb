# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/commands/agent_command_router'

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

  # Harvesting tests

  DISCONNECTING = true
  NOT_DISCONNECTING = false

  def test_harvest_data_to_send_not_started
    result = agent_commands.harvest_data_to_send(NOT_DISCONNECTING)
    assert_equal({}, result)
  end

  def test_harvest_data_to_send_with_profile_in_progress
    with_profile(:finished => false)
    result = agent_commands.harvest_data_to_send(NOT_DISCONNECTING)
    assert_equal({}, result)
  end

  def test_harvest_data_to_send_with_profile_completed
    expected_profile = with_profile(:finished => true)
    result = agent_commands.harvest_data_to_send(NOT_DISCONNECTING)
    assert_equal({:profile_data => expected_profile}, result)
  end

  def test_harvest_data_to_send_with_profile_in_progress_but_disconnecting
    expected_profile = with_profile(:finished => false)
    result = agent_commands.harvest_data_to_send(DISCONNECTING)
    assert_equal({:profile_data => expected_profile}, result)
  end

  # Helpers

  def handle_bazzle_command(command)
    calls << command.arguments
  end

  def handle_boom_command(command)
    raise NewRelic::Agent::Commands::AgentCommandRouter::AgentCommandError.new("BOOOOOM")
  end

  def with_profile(opts)
    profile = NewRelic::Agent::Threading::ThreadProfile.new
    profile.aggregate(["chunky.rb:42:in `bacon'"], :other)
    profile.mark_done if opts[:finished]

    agent_commands.thread_profiler_session.profile = profile
    profile
  end

end
