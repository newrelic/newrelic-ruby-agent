# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/commands/agent_command'

module NewRelic::Agent::Commands
  class AgentCommandTest < Minitest::Test
    ID = 123
    NAME = 'nuke_it_from_orbit'
    ARGUMENTS = { "profile_id" => 42 }

    NUKE_IT_FROM_ORBIT = [ID,{
      "name" => NAME,
      "arguments" => ARGUMENTS
    }]

    def test_destructures_name_from_collector_command
      command = AgentCommand.new(NUKE_IT_FROM_ORBIT)
      expected = NAME
      assert_equal expected, command.name
    end

    def test_destructures_id_from_collector_command
      command = AgentCommand.new(NUKE_IT_FROM_ORBIT)
      expected = ID
      assert_equal expected, command.id
    end

    def test_destructures_arguments_from_collector_command
      command = AgentCommand.new(NUKE_IT_FROM_ORBIT)
      expected = ARGUMENTS
      assert_equal expected, command.arguments
    end
  end
end
