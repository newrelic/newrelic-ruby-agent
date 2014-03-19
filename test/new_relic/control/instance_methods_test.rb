# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))
require 'new_relic/control/instance_methods'

class TestClass
  include NewRelic::Control::InstanceMethods
end

class NewRelic::Control::InstanceMethodsTest < Minitest::Test
  def setup
    NewRelic::Agent.config.reset_to_defaults
    @test = ::TestClass.new(nil)
  end

  def test_configure_agent_adds_the_yaml_config
    refute NewRelic::Agent.config.contains_source? :yaml
    @test.configure_agent('test', {})
    assert NewRelic::Agent.config.contains_source? :yaml
  end

  def test_configure_agent_adds_the_manual_config
    refute NewRelic::Agent.config.contains_source? :manual
    @test.configure_agent('test', {})
    assert NewRelic::Agent.config.contains_source? :manual
  end
end
