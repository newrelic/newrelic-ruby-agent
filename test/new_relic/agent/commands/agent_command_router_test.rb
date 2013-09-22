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

    @agent_commands = NewRelic::Agent::Commands::AgentCommandRouter.new(nil)
    @agent_commands.handlers["bazzle"] = Proc.new { |args| handle_bazzle_command(args) }
    @agent_commands.handlers["boom"]   = Proc.new { |args| handle_boom_command(args) }
  end

  def test_handle_agent_commands_dispatches_command
    service.stubs(:get_agent_commands).returns([BAZZLE])
    service.stubs(:agent_command_results)

    agent_commands.handle_agent_commands

    assert_equal [DEFAULT_ARGS], calls
  end

  def test_handle_agent_commands_generates_results
    service.stubs(:get_agent_commands).returns([BAZZLE])
    service.expects(:agent_command_results).with({ BAZZLE_ID.to_s => {} })

    agent_commands.handle_agent_commands
  end

  def test_handle_agent_commands_dispatches_with_error
    service.stubs(:get_agent_commands).returns([BOOM])
    service.expects(:agent_command_results).with({ BOOM_ID.to_s => { "error" => "BOOOOOM" }})

    agent_commands.handle_agent_commands
  end

  def test_handle_agent_commands_allows_multiple
    service.stubs(:get_agent_commands).returns([BAZZLE, BOOM])
    service.expects(:agent_command_results).with({ BAZZLE_ID.to_s => {},
                                                   BOOM_ID.to_s => { "error" => "BOOOOOM" }})
    agent_commands.handle_agent_commands
  end

  def test_handle_agent_commands_doesnt_call_results_if_no_commands
    service.stubs(:get_agent_commands).returns([])
    service.expects(:agent_command_results).never

    agent_commands.handle_agent_commands
  end

  def test_unrecognized_commands
    service.stubs(:get_agent_commands).returns([UNRECOGNIZED])
    service.stubs(:agent_command_results)

    expects_logging(:debug, regexp_matches(/unrecognized/i))

    agent_commands.handle_agent_commands
  end

  # Helpers

  def handle_bazzle_command(command)
    calls << command.arguments
  end

  def handle_boom_command(command)
    raise NewRelic::Agent::Commands::AgentCommandRouter::AgentCommandError.new("BOOOOOM")
  end
end
