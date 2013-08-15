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

  def setup
    @service = stub(:agent_command_results)

    @agent_commands = NewRelic::Agent::Commands::AgentCommandRouter.new(@service, nil)

    @handler = TestHandler.new
    @agent_commands.handlers["bazzle"] = Proc.new { |args| @handler.handle_bazzle_command(args) }
    @agent_commands.handlers["boom"] = Proc.new { |args| @handler.handle_boom_command(args) }
  end

  def test_handle_agent_commands_dispatches_command
    with_commands(BAZZLE)
    @agent_commands.handle_agent_commands
    assert_equal [DEFAULT_ARGS], @handler.calls
  end

  def test_handle_agent_commands_generates_results
    with_commands(BAZZLE)
    @service.expects(:agent_command_results).with({ BAZZLE_ID.to_s => {} })
    @agent_commands.handle_agent_commands
  end

  def test_handle_agent_commands_dispatches_with_error
    with_commands(BOOM)
    @service.expects(:agent_command_results).with({ BOOM_ID.to_s => { "error" => "BOOOOOM" }})
    @agent_commands.handle_agent_commands
  end

  def test_handle_agent_commands_allows_multiple
    with_commands(BAZZLE, BOOM)
    @service.expects(:agent_command_results).with({ BAZZLE_ID.to_s => {},
                                                    BOOM_ID.to_s => { "error" => "BOOOOOM" }})
    @agent_commands.handle_agent_commands
  end

  # Helpers

  class TestHandler
    attr_accessor :calls

    def initialize
      @calls = []
    end

    def handle_bazzle_command(command)
      calls << command
    end

    def handle_boom_command(command)
      calls << command
      raise NewRelic::Agent::Commands::AgentCommandRouter::AgentCommandError.new("BOOOOOM")
    end
  end

  def with_commands(*cmds)
    @service.stubs(:get_agent_commands).returns(cmds)
  end
end
