# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require 'new_relic/control/security_interface'

class NewRelic::Control::SecurityInterfaceTest < Minitest::Test
  def setup
    NewRelic::Agent.config.reset_to_defaults
    %i[@agent_started @wait].each do |variable|
      instance = NewRelic::Control::SecurityInterface.instance
      instance.remove_instance_variable(variable) if instance.instance_variable_defined?(variable)
    end
  end

  # For testing purposes, clear out the supportability metrics that have already been recorded.
  def reset_supportability_metrics
    NewRelic::Agent.instance_variable_get(:@metrics_already_recorded)&.clear
  end

  def assert_supportability_metrics_enabled
    assert_metrics_recorded 'Supportability/Ruby/SecurityAgent/Agent/Enabled/enabled'
  end

  def test_initialization_short_circuits_when_the_security_agent_is_disabled
    reset_supportability_metrics

    logger = MiniTest::Mock.new
    with_config('security.agent.enabled' => false, 'high_security' => false) do
      NewRelic::Agent.stub :logger, logger do
        logger.expect :info, nil, [/Security is completely disabled/]
        logger.expect :info, nil, [/high_security = false/]
        logger.expect :info, nil, [/security.agent.enabled = false/]

        NewRelic::Control::SecurityInterface.instance.init_agent
      end

      refute_predicate NewRelic::Control::SecurityInterface.instance, :agent_started?
      assert_metrics_recorded 'Supportability/Ruby/SecurityAgent/Agent/Enabled/disabled'
    end
    logger.verify
  end

  def test_initialization_short_circuits_when_high_security_mode_is_enabled
    logger = MiniTest::Mock.new
    with_config('security.agent.enabled' => true, 'high_security' => true) do
      NewRelic::Agent.stub :logger, logger do
        logger.expect :info, nil, [/Security is completely disabled/]
        logger.expect :info, nil, [/high_security = true/]
        logger.expect :info, nil, [/security.agent.enabled = true/]

        NewRelic::Control::SecurityInterface.instance.init_agent
      end

      refute_predicate NewRelic::Control::SecurityInterface.instance, :agent_started?
      assert_supportability_metrics_enabled
    end
    logger.verify
  end

  def test_initialization_short_circuits_if_the_agent_has_already_been_started
    reached = false
    with_config('security.agent.enabled' => true) do
      NewRelic::Agent.stub :config, -> { reached = true } do
        NewRelic::Control::SecurityInterface.instance.instance_variable_set(:@agent_started, true)
        NewRelic::Control::SecurityInterface.instance.init_agent
      end
    end

    refute reached, 'Expected init_agent to short circuit but it reached code within the method instead!'
  end

  def test_initialization_short_circuits_if_the_agent_has_been_told_to_wait
    reached = false
    with_config('security.agent.enabled' => true) do
      NewRelic::Agent.stub :config, -> { reached = true } do
        NewRelic::Control::SecurityInterface.instance.instance_variable_set(:@wait, true)
        NewRelic::Control::SecurityInterface.instance.init_agent
      end
    end

    refute reached, 'Expected init_agent to short circuit but it reached code within the method instead!'
  end

  def test_initialization_requires_the_security_agent
    skip_unless_minitest5_or_above

    required = false
    logger = MiniTest::Mock.new
    with_config('security.agent.enabled' => true) do
      NewRelic::Agent.stub :logger, logger do
        logger.expect :info, nil, [/Invoking New Relic security/]

        NewRelic::Control::SecurityInterface.instance.stub :require, proc { |_gem| required = true }, %w[newrelic_security] do
          NewRelic::Control::SecurityInterface.instance.init_agent
        end
      end
    end
    logger.verify

    assert required, 'Expected init_agent to perform a require statement'
    assert_predicate NewRelic::Control::SecurityInterface.instance, :agent_started?
    assert_supportability_metrics_enabled
  end

  def test_initialization_anticipates_a_load_error
    skip_unless_minitest5_or_above

    logger = MiniTest::Mock.new
    with_config('security.agent.enabled' => true) do
      NewRelic::Agent.stub :logger, logger do
        logger.expect :info, nil, [/Invoking New Relic security/]
        logger.expect :info, nil, [/security agent not found/]

        error_proc = proc { |_gem| raise LoadError.new }
        NewRelic::Control::SecurityInterface.instance.stub :require, error_proc, %w[newrelic_security] do
          NewRelic::Control::SecurityInterface.instance.init_agent
        end
      end
      logger.verify

      refute_predicate NewRelic::Control::SecurityInterface.instance, :agent_started?
      assert_supportability_metrics_enabled
    end
  end

  def test_initialization_handles_errors
    skip_unless_minitest5_or_above

    logger = MiniTest::Mock.new
    with_config('security.agent.enabled' => true) do
      NewRelic::Agent.stub :logger, logger do
        logger.expect :info, nil, [/Invoking New Relic security/]
        logger.expect :error, nil, [/Exception in New Relic security module loading/]

        error_proc = proc { |_gem| raise StandardError }
        NewRelic::Control::SecurityInterface.instance.stub :require, error_proc, %w[newrelic_security] do
          NewRelic::Control::SecurityInterface.instance.init_agent
        end
      end
    end
    logger.verify

    refute_predicate NewRelic::Control::SecurityInterface.instance, :agent_started?
    assert_supportability_metrics_enabled
  end
end
