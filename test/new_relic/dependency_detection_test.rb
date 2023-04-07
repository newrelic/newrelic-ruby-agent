# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../test_helper'

class DependencyDetectionTest < Minitest::Test
  def setup
    @original_items = DependencyDetection.instance_variable_get(:@items)
    DependencyDetection.instance_variable_set(:@items, [])
  end

  def teardown
    DependencyDetection.instance_variable_set(:@items, @original_items)
  end

  def test_passes_dependency
    executed = false

    DependencyDetection.defer do
      depends_on { true }
      executes { executed = true }
    end
    DependencyDetection.detect!

    assert executed
  end

  def test_falls_back_to_name_for_config_key
    key = nil

    DependencyDetection.defer do
      named(:testing)
      executes { key = config_key }
    end
    DependencyDetection.detect!

    assert_equal :"instrumentation.testing", key
  end

  def test_uses_config_name_for_config_key
    key = nil

    DependencyDetection.defer do
      named(:testing)
      configure_with(:alternate)
      executes { key = config_key }
    end
    DependencyDetection.detect!

    assert_equal :"instrumentation.alternate", key
  end

  def test_fails_dependency
    executed = false

    DependencyDetection.defer do
      depends_on { true }
      depends_on { false }
      executes { executed = true }
    end
    DependencyDetection.detect!

    refute executed
  end

  def test_short_circuits_on_failure
    executed = false

    # Requires that depends_on would let failures pass through, which it does
    DependencyDetection.defer do
      depends_on { false }
      depends_on { raise 'OH NOES' }
      executes { executed = true }
    end
    DependencyDetection.detect!

    refute executed
  end

  def test_named_disabling_defaults_to_allowed
    executed = false

    DependencyDetection.defer do
      named(:testing)
      executes { executed = true }
    end
    DependencyDetection.detect!

    assert executed
  end

  def test_named_disabling_allows_with_explicit_value
    executed = false

    DependencyDetection.defer do
      named(:testing)
      executes { executed = true }
    end

    with_config(:disable_testing => false) do
      DependencyDetection.detect!
    end

    assert executed
  end

  def test_named_disabling
    executed = false

    DependencyDetection.defer do
      named(:testing)
      executes { executed = true }
    end

    with_config(:disable_testing => true) do
      DependencyDetection.detect!
    end

    refute executed
  end

  def test_config_defaults_to_auto
    setting = nil

    DependencyDetection.defer do
      named(:testing)
      executes { setting = config_value }
    end
    DependencyDetection.detect!

    assert_equal :auto, setting
  end

  def test_config_disabling
    executed = false

    dd = DependencyDetection.defer do
      named(:testing)
      executes { executed = true }
    end

    with_config(:'instrumentation.testing' => 'disabled') do
      executed = false
      DependencyDetection.detect!

      assert_predicate dd, :disabled_configured?
      refute dd.deprecated_disabled_configured?
      refute dd.allowed_by_config?
      refute executed
    end

    with_config(:'instrumentation.testing' => 'enabled') do
      executed = false
      DependencyDetection.detect!

      refute dd.disabled_configured?
      refute dd.deprecated_disabled_configured?
      assert_predicate dd, :allowed_by_config?
      assert executed
    end

    # TODO: MAJOR VERSION - Deprecated!
    with_config(:disable_testing => true) do
      executed = false
      DependencyDetection.detect!

      refute dd.disabled_configured?
      assert_predicate dd, :deprecated_disabled_configured?
      refute dd.allowed_by_config?
      refute executed
    end
  end

  def test_config_enabling
    executed = false

    dd = DependencyDetection.defer do
      named(:testing)
      executes { executed = true }
    end

    with_config(:'instrumentation.testing' => 'enabled') do
      executed = false
      DependencyDetection.detect!

      refute dd.disabled_configured?
      refute dd.deprecated_disabled_configured?
      assert executed
      assert_predicate dd, :use_prepend?
    end

    with_config(:'instrumentation.testing' => 'auto') do
      DependencyDetection.detect!

      refute dd.disabled_configured?
      refute dd.deprecated_disabled_configured?
      assert_predicate dd, :use_prepend?
    end

    with_config(:'instrumentation.testing' => 'prepend') do
      DependencyDetection.detect!

      refute dd.disabled_configured?
      refute dd.deprecated_disabled_configured?
      assert_predicate dd, :use_prepend?
    end

    with_config(:'instrumentation.testing' => 'chain') do
      DependencyDetection.detect!

      refute dd.disabled_configured?
      refute dd.deprecated_disabled_configured?
      refute dd.use_prepend?
    end
  end

  def test_config_prepend
    dd = DependencyDetection.defer do
      named(:testing)
      executes { true }
    end

    with_config({}) do
      DependencyDetection.detect!

      assert_equal :auto, dd.config_value
      assert_predicate dd, :use_prepend?
    end

    with_config(:'instrumentation.testing' => 'prepend') do
      DependencyDetection.detect!

      assert_equal :prepend, dd.config_value
      assert_predicate dd, :use_prepend?
    end

    with_config(:'instrumentation.testing' => 'disabled') do
      DependencyDetection.detect!

      refute dd.use_prepend?
    end
  end

  def test_selects_chain_method_explicitly
    executed = false

    dd = DependencyDetection.defer do
      named(:testing)
      executes { executed = true }
    end

    with_config(:'instrumentation.testing' => 'chain') do
      DependencyDetection.detect!

      refute dd.use_prepend?
      assert_equal :chain, dd.config_value
      assert executed
    end
  end

  def test_conflicts_simple_truthy
    conflicted = nil

    DependencyDetection.defer do
      conflicts_with_prepend { true }
      executes { conflicted = prepend_conflicts? }
    end

    DependencyDetection.detect!

    assert conflicted, 'should be truthy!'
  end

  def test_conflicts_simple_falsey
    conflicted = nil

    DependencyDetection.defer do
      conflicts_with_prepend { false }
      executes { conflicted = prepend_conflicts? }
    end

    DependencyDetection.detect!

    refute conflicted, 'should be falsey!'
  end

  def test_conflicts_defined_falsey
    conflicted = nil

    dd = DependencyDetection.defer do
      conflicts_with_prepend { defined?(Thingamajig) }
      executes { conflicted = prepend_conflicts? }
    end

    DependencyDetection.detect!

    refute conflicted, 'should be falsey!'
    assert_predicate dd, :use_prepend?, 'should use prepend when no conflicts exist'
  end

  def test_conflicts_defined_truthy
    conflicted = nil

    dd = DependencyDetection.defer do
      conflicts_with_prepend { defined?(Object) }
      executes { conflicted = prepend_conflicts? }
    end

    DependencyDetection.detect!

    assert conflicted, 'should be truthy!'
    refute dd.use_prepend?, 'should not use prepend when conflicts exist'
  end

  def test_conflicts_multiples_truthy
    conflicted = nil

    dd = DependencyDetection.defer do
      conflicts_with_prepend { defined?(Thingamajig) }
      conflicts_with_prepend { defined?(Object) }
      executes { conflicted = prepend_conflicts? }
    end

    DependencyDetection.detect!

    assert conflicted, 'should be truthy!'
    refute dd.use_prepend?, 'should not use prepend when conflicts exist'
  end

  def test_exception_during_depends_on_check_doesnt_propagate
    DependencyDetection.defer do
      named(:something_exceptional)
      depends_on { raise 'Oops' }
    end

    DependencyDetection.detect!

    assert_falsy(DependencyDetection.instance_variable_get(:@items).first.executed)
  end

  def test_exception_during_execution_doesnt_propagate
    ran_second_block = false

    DependencyDetection.defer do
      named(:something_exceptional)
      executes { raise 'Ack!' }
      executes { ran_second_block = true }
    end

    DependencyDetection.detect!

    assert_truthy(DependencyDetection.instance_variable_get(:@items).first.executed)
    assert_falsy(ran_second_block)
  end

  def test_defer_should_be_idempotent_when_given_same_name
    run_count = 0

    2.times do
      DependencyDetection.defer do
        named(:foobar)
        executes { run_count += 1 }
      end
    end

    DependencyDetection.detect!

    assert_equal(1, run_count)
  end

  def test_log_and_instrument_uses_supportability_name_when_provided
    method = 'Stanislavski'
    supportability_name = 'Magic::If'
    log = with_array_logger do
      DependencyDetection::Dependent.new.log_and_instrument(method, 'actor', supportability_name) { 'Given Circumstances' }
    end

    assert_metrics_recorded("Supportability/Instrumentation/#{supportability_name}/#{method}")
    assert_log_contains(log, /#{supportability_name}/)
    assert_log_contains(log, /#{method}/)
  end

  # when an instrumentation value of :auto (the default) is present, the agent
  # automatically determines whether to use :prepend or :chain. after the
  # determination is made, the config value should be updated to be either
  # :prepend or :chain so that the determined value can be introspected.
  def test_prepend_or_chain_based_values_have_auto_converted_into_one_of_those
    name = :bandu_gumbo

    dd = DependencyDetection.defer do
      named(name)
      executes { use_prepend? }
    end

    with_config(:"instrumentation.#{name}" => 'auto') do
      DependencyDetection.detect!

      assert_equal :prepend, dd.config_value
    end
  end

  # confirm that :auto becames :chain when :chain is automatically determined
  def test_auto_is_replaced_by_chain_when_chain_is_used
    name = :blank_and_jones

    dd = DependencyDetection.defer do
      named(name)
      conflicts_with_prepend { true }
      executes { use_prepend? }
    end

    with_config(:"instrumentation.#{name}" => 'auto') do
      DependencyDetection.detect!

      assert_equal :chain, dd.config_value
    end
  end
end
