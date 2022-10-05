# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require 'new_relic/control/instance_methods'
require 'new_relic/agent/configuration/yaml_source'

class TestClass
  include NewRelic::Control::InstanceMethods
  def stdout
    @stdout ||= StringIO.new
  end
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

  def test_configure_agent_yaml_parse_error_logs_to_stdout
    NewRelic::Agent::Configuration::YamlSource.any_instance.stubs(:failed?).returns(true)
    NewRelic::Agent::Configuration::YamlSource.any_instance.stubs(:failures).returns(['failure'])
    @test.configure_agent('invalid', {})
    assert_equal "** [NewRelic] FATAL : failure\n", @test.stdout.string
  end

  def test_configure_agent_invalid_yaml_value_logs_to_stdout
    config_path = File.expand_path(File.join(
      File.dirname(__FILE__),
      '..', '..', 'config', 'newrelic.yml'
    ))
    @test.configure_agent('invalid', {:config_path => config_path})
    assert NewRelic::Agent.config.instance_variable_get(:@yaml_source).failed?
    expected_err = "** [NewRelic] FATAL : Unexpected value (cultured groats) for 'enabled' in #{config_path}\n"
    assert_equal expected_err, @test.stdout.string
  end

  def refute_has_config(clazz)
    refute_includes NewRelic::Agent.config.config_classes_for_testing, clazz
  end

  def assert_has_config(clazz)
    assert_includes(NewRelic::Agent.config.config_classes_for_testing, clazz)
  end
end
