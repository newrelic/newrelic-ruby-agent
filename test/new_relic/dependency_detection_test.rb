# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative '../test_helper'

class DependencyDetectionTest < Minitest::Test
  def setup
    @original_items = DependencyDetection.items
    DependencyDetection.items = []
  end

  def teardown
    DependencyDetection.items = @original_items
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
      named :testing
      executes { key = config_key }
    end
    DependencyDetection.detect!

    assert_equal :"instrumentation.testing", key
  end

  def test_uses_config_name_for_config_key
    key = nil

    DependencyDetection.defer do
      named :testing
      configure_with :alternate
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

    assert !executed
  end

  def test_short_circuits_on_failure
    executed = false

    # Requires that depends_on would let failures pass through, which it does
    DependencyDetection.defer do
      depends_on { false }
      depends_on { raise "OH NOES" }
      executes { executed = true }
    end
    DependencyDetection.detect!

    assert !executed
  end

  def test_named_disabling_defaults_to_allowed
    executed = false

    DependencyDetection.defer do
      named :testing
      executes { executed = true }
    end
    DependencyDetection.detect!

    assert executed
  end

  def test_named_disabling_allows_with_explicit_value
    executed = false

    DependencyDetection.defer do
      named :testing
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
      named :testing
      executes { executed = true }
    end

    with_config(:disable_testing => true) do
      DependencyDetection.detect!
    end

    assert !executed
  end

  def test_config_defaults_to_auto
    setting = nil

    DependencyDetection.defer do
      named :testing
      executes { setting = config_value }
    end
    DependencyDetection.detect!

    assert_equal :auto, setting
  end

  def test_config_disabling
    executed = false

    dd = DependencyDetection.defer do
      named :testing
      executes { executed = true }
    end

    with_config(:'instrumentation.testing' => "disabled") do
      executed = false
      DependencyDetection.detect!
      assert dd.disabled_configured?
      refute dd.deprecated_disabled_configured?
      refute dd.allowed_by_config?
      refute executed
    end

    with_config(:'instrumentation.testing' => "enabled") do
      executed = false
      DependencyDetection.detect!
      refute dd.disabled_configured?
      refute dd.deprecated_disabled_configured?
      assert dd.allowed_by_config?
      assert executed
    end

    # TODO: MAJOR VERSION - Deprecated!
    with_config(:disable_testing => true) do
      executed = false
      DependencyDetection.detect!
      refute dd.disabled_configured?
      assert dd.deprecated_disabled_configured?
      refute dd.allowed_by_config?
      refute executed
    end
  end

  def test_config_enabling
    executed = false

    dd = DependencyDetection.defer do
      named :testing
      executes { executed = true }
    end

    with_config(:'instrumentation.testing' => "enabled") do
      executed = false
      DependencyDetection.detect!
      refute dd.disabled_configured?
      refute dd.deprecated_disabled_configured?
      assert executed
      assert dd.use_prepend?
    end

    with_config(:'instrumentation.testing' => "auto") do
      DependencyDetection.detect!
      refute dd.disabled_configured?
      refute dd.deprecated_disabled_configured?
      assert dd.use_prepend?
    end

    with_config(:'instrumentation.testing' => "prepend") do
      DependencyDetection.detect!
      refute dd.disabled_configured?
      refute dd.deprecated_disabled_configured?
      assert dd.use_prepend?
    end

    with_config(:'instrumentation.testing' => "chain") do
      DependencyDetection.detect!
      refute dd.disabled_configured?
      refute dd.deprecated_disabled_configured?
      refute dd.use_prepend?
    end
  end

  def test_config_prepend
    executed = false

    dd = DependencyDetection.defer do
      named :testing
      executes { executed = true }
    end

    with_config({}) do
      DependencyDetection.detect!
      assert_equal :auto, dd.config_value
      assert dd.use_prepend?
    end

    with_config(:'instrumentation.testing' => "prepend") do
      DependencyDetection.detect!
      assert_equal :prepend, dd.config_value
      assert dd.use_prepend?
    end

    with_config(:'instrumentation.testing' => "disabled") do
      DependencyDetection.detect!
      refute dd.use_prepend?
    end
  end

  def test_selects_chain_method_explicitly
    executed = false

    dd = DependencyDetection.defer do
      named :testing
      executes { executed = true }
    end

    with_config(:'instrumentation.testing' => "chain") do
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

    assert conflicted, "should be truthy!"
  end

  def test_conflicts_simple_falsey
    conflicted = nil

    DependencyDetection.defer do
      conflicts_with_prepend { false }
      executes { conflicted = prepend_conflicts? }
    end

    DependencyDetection.detect!

    refute conflicted, "should be falsey!"
  end

  def test_conflicts_defined_falsey
    conflicted = nil

    dd = DependencyDetection.defer do
      conflicts_with_prepend { defined?(Thingamajig) }
      executes { conflicted = prepend_conflicts? }
    end

    DependencyDetection.detect!

    refute conflicted, "should be falsey!"
    assert dd.use_prepend?, "should use prepend when no conflicts exist"
  end

  def test_conflicts_defined_truthy
    conflicted = nil

    dd = DependencyDetection.defer do
      conflicts_with_prepend { defined?(Object) }
      executes { conflicted = prepend_conflicts? }
    end

    DependencyDetection.detect!

    assert conflicted, "should be truthy!"
    refute dd.use_prepend?, "should not use prepend when conflicts exist"
  end

  def test_conflicts_multiples_truthy
    conflicted = nil

    dd = DependencyDetection.defer do
      conflicts_with_prepend { defined?(Thingamajig) }
      conflicts_with_prepend { defined?(Object) }
      executes { conflicted = prepend_conflicts? }
    end

    DependencyDetection.detect!

    assert conflicted, "should be truthy!"
    refute dd.use_prepend?, "should not use prepend when conflicts exist"
  end

  def test_exception_during_depends_on_check_doesnt_propagate
    DependencyDetection.defer do
      named :something_exceptional
      depends_on { raise "Oops" }
    end

    DependencyDetection.detect!

    assert_falsy(DependencyDetection.items.first.executed)
  end

  def test_exception_during_execution_doesnt_propagate
    ran_second_block = false

    DependencyDetection.defer do
      named :something_exceptional
      executes { raise "Ack!" }
      executes { ran_second_block = true }
    end

    DependencyDetection.detect!

    assert_truthy(DependencyDetection.items.first.executed)
    assert_falsy(ran_second_block)
  end

  def test_defer_should_be_idempotent_when_given_same_name
    run_count = 0

    2.times do
      DependencyDetection.defer do
        named :foobar
        executes { run_count += 1 }
      end
    end

    DependencyDetection.detect!

    assert_equal(1, run_count)
  end
end
