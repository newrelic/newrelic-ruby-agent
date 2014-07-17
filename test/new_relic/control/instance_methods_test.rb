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
    refute_has_config NewRelic::Agent::Configuration::YamlSource
    @test.configure_agent('test', {})
    assert_has_config NewRelic::Agent::Configuration::YamlSource
  end

  def test_configure_agent_adds_the_manual_config
    refute_has_config NewRelic::Agent::Configuration::ManualSource
    @test.configure_agent('test', {})
    assert_has_config NewRelic::Agent::Configuration::ManualSource
  end

  def test_no_high_security_config_by_default
    refute_has_config NewRelic::Agent::Configuration::HighSecuritySource
    @test.configure_agent('test', {:high_security => false})
    refute_has_config NewRelic::Agent::Configuration::HighSecuritySource
  end

  def test_high_security_config_added_if_requested
    refute_has_config NewRelic::Agent::Configuration::HighSecuritySource
    @test.configure_agent('test', {:high_security => true})
    assert_has_config NewRelic::Agent::Configuration::HighSecuritySource
  end

  def refute_has_config(clazz)
    refute NewRelic::Agent.config.config_classes_for_testing.include? clazz
  end

  def assert_has_config(clazz)
    assert NewRelic::Agent.config.config_classes_for_testing.include? clazz
  end
end
