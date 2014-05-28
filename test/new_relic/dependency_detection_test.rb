# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','test_helper'))

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
      executes   { executed = true }
    end
    DependencyDetection.detect!

    assert executed
  end

  def test_fails_dependency
    executed = false

    DependencyDetection.defer do
      depends_on { true }
      depends_on { false }
      executes   { executed = true }
    end
    DependencyDetection.detect!

    assert !executed
  end

  def test_short_circuits_on_failure
    executed = false

    # Requires that depends_on would let failures pass through, which it does
    DependencyDetection.defer do
      depends_on { false }
      depends_on { raise "OH NOES"}
      executes   { executed = true }
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

  def test_named_disabling_with_instance_variable
    executed = false

    DependencyDetection.defer do
      @name = :testing
      executes { executed = true }
    end

    with_config(:disable_testing => true) do
      DependencyDetection.detect!
    end

    assert !executed
  end

  def test_exception_during_depends_on_check_doesnt_propagate
    DependencyDetection.defer do
      named :something_exceptional
      depends_on { raise "Oops" }
    end

    DependencyDetection.detect!

    assert_falsy( DependencyDetection.items.first.executed )
  end


  def test_exception_during_execution_doesnt_propagate
    ran_second_block = false

    DependencyDetection.defer do
      named :something_exceptional
      executes { raise "Ack!" }
      executes { ran_second_block = true }
    end

    DependencyDetection.detect!

    assert_truthy( DependencyDetection.items.first.executed )
    assert_falsy( ran_second_block )
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
