# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))
require 'new_relic/control/instance_methods'
require 'new_relic/agent/configuration/yaml_source'

class TestClass
  include NewRelic::Control::InstanceMethods
end

class NewRelic::Control::InstanceMethodsTest < Minitest::Test
  def setup
    NewRelic::Agent.config.reset_to_defaults
    @test = ::TestClass.new(nil)
  end

  def test_configure_agent_adds_the_yaml_config
    refute NewRelic::Agent.config.config_stack_index_for NewRelic::Agent::Configuration::YamlSource
    @test.configure_agent('test', {})
    assert NewRelic::Agent.config.config_stack_index_for NewRelic::Agent::Configuration::YamlSource
  end

  def test_configure_agent_adds_the_manual_config
    refute NewRelic::Agent.config.config_stack_index_for NewRelic::Agent::Configuration::ManualSource
    @test.configure_agent('test', {})
    assert NewRelic::Agent.config.config_stack_index_for NewRelic::Agent::Configuration::ManualSource
  end
end
