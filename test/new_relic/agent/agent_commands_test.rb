# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/agent_commands'

class AgentCommandsTest < Test::Unit::TestCase

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

    @agent_commands = NewRelic::Agent::AgentCommands.new

    @handler = TestHandler.new
    @agent_commands.add_handler("bazzle", @handler, :respond_to_bazzle)
    @agent_commands.add_handler("boom",   @handler, :respond_to_boom)
  end

  def test_check_for_agent_commands_dispatches_command
    with_commands(BAZZLE)

    @agent_commands.check_for_agent_commands(@service)

    assert_equal [[BAZZLE_ID, "bazzle", DEFAULT_ARGS]], @handler.calls
  end

  def test_check_for_agent_commands_hits_callback
    with_commands(BAZZLE)
    @service.expects(:agent_command_results).with(BAZZLE_ID, nil)

    @agent_commands.check_for_agent_commands(@service)
  end

  def test_check_for_agent_commands_dispatches_command_with_error
    with_commands(BOOM)
    @service.expects(:agent_command_results).with(BOOM_ID, "BOOOOOM")

    @agent_commands.check_for_agent_commands(@service)
  end

  def test_check_for_agent_commands_allows_multiple
    with_commands(BAZZLE, BOOM)
    @service.expects(:agent_command_results).with(BAZZLE_ID, nil)
    @service.expects(:agent_command_results).with(BOOM_ID, "BOOOOOM")

    @agent_commands.check_for_agent_commands(@service)
  end

  def test_responds_to_message
    @agent_commands.respond_to(BAZZLE)
    assert_equal 1, @handler.calls.size
  end

  def test_responds_to_message_with_callback
    called = false
    @agent_commands.respond_to(BAZZLE) { |*_| called = true}
    assert called
  end

  # Helpers

  class TestHandler
    attr_accessor :calls

    def initialize
      @calls = []
    end

    def respond_to_bazzle(command_id, name, arguments, &results_callback)
      calls << [command_id, name, arguments]
      results_callback.call(command_id) unless results_callback.nil?
    end

    def respond_to_boom(command_id, name, arguments, &results_callback)
      calls << [command_id, name, arguments]
      results_callback.call(command_id, "BOOOOOM") unless results_callback.nil?
    end
  end

  def with_commands(*cmds)
    @service.stubs(:get_agent_commands).returns(cmds)
  end
end
