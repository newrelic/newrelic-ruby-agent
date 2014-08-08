# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))
require 'new_relic/control/instrumentation'

class InstrumentationTestClass
  include NewRelic::Control::Instrumentation

  def initialize
    @instrumentation_files = []
  end
end

class NewRelic::Control::InstrumentationTest < Minitest::Test
  def setup
    @test_class = InstrumentationTestClass.new
  end

  def test_load_instrumentation_files_logs_errors_during_require
    @test_class.stubs(:require).raises('Instrumentation Test Error')
    expects_logging(:warn, includes("Error loading"), any_parameters)
    @test_class.load_instrumentation_files '*'
  end

  def test_add_instrumentation_loads_the_instrumentation_files_if_instrumented
    pattern = 'Instrumentation test pattern'
    @test_class.instance_eval { @instrumented = true }
    @test_class.expects(:load_instrumentation_files).with(pattern).once
    @test_class.add_instrumentation(pattern)
  end

  def test_add_instrumentation_adds_pattern_to_instrumentation_files_if_uninstrumented
    expected_pattern = 'Instrumentation test pattern'
    @test_class.instance_eval { @instrumented = false }
    @test_class.add_instrumentation(expected_pattern)
    result = @test_class.instance_variable_get(:@instrumentation_files)
    assert_equal [expected_pattern], result
  end

  def test_install_shim_logs_if_instrumentation_has_already_been_installed
    @test_class.instance_eval { @instrumented = true }
    expects_logging(:error, includes('Cannot install'))
    @test_class.install_shim
  end

  def test_install_shim_does_not_set_agent_if_already_instrumented
    fake_shim = "Instrumentation Test Shim Agent"
    @test_class.instance_eval { @instrumented = true }
    NewRelic::Agent::ShimAgent.class_eval { @instance = fake_shim }

    @test_class.install_shim
    refute_equal NewRelic::Agent.agent, fake_shim
  end
end
