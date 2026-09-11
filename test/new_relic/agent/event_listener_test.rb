# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'

class EventListenerTest < Minitest::Test
  def setup
    @events = NewRelic::Agent::EventListener.new

    @called = false
    @called_with = nil

    @check_method = proc do |*args|
      @called = true
      @called_with = args
    end
  end

  #
  # Helpers
  #

  def assert_was_called
    assert @called, "Event wasn't called"
  end

  def assert_was_not_called
    refute @called, 'Event was called'
  end

  #
  # Tests
  #

  def test_notifies
    @events.subscribe(:before_call, &@check_method)
    @events.notify(:before_call, :env => 'env')

    assert_was_called
    assert_equal([{:env => 'env'}], @called_with)
  end

  def test_failure_during_notify_doesnt_block_other_hooks
    @events.subscribe(:after_call) { raise 'Boo!' }
    @events.subscribe(:after_call, &@check_method)

    @events.notify(:after_call)

    assert_was_called
  end

  def test_runaway_events
    @events.runaway_threshold = 0
    expects_logging(:debug, includes('my_event'))
    @events.subscribe(:my_event) {}
  end

  def test_clear
    @events.subscribe(:after_call, &@check_method)
    @events.clear
    @events.notify(:after_call)

    assert_was_not_called
  end

  def test_subscribe_returns_the_handler
    handler = @events.subscribe(:after_call, &@check_method)

    assert_equal @check_method, handler
  end

  def test_unsubscribe_removes_only_the_given_handler
    other_called = false
    handler = @events.subscribe(:after_call, &@check_method)
    @events.subscribe(:after_call) { other_called = true }

    @events.unsubscribe(:after_call, handler)
    @events.notify(:after_call)

    assert_was_not_called
    assert other_called
  end

  def test_unsubscribe_removes_every_occurrence_of_a_duplicate_handler
    @events.subscribe(:after_call, &@check_method)
    @events.subscribe(:after_call, &@check_method)

    @events.unsubscribe(:after_call, @check_method)
    @events.notify(:after_call)

    assert_was_not_called
  end

  def test_unsubscribe_is_a_no_op_for_an_unrecognized_event
    @events.unsubscribe(:after_call, @check_method)
    @events.notify(:after_call)

    assert_was_not_called
  end

  def test_unsubscribe_is_a_no_op_for_a_handler_that_was_never_subscribed
    @events.subscribe(:after_call, &@check_method)
    unknown_handler = proc {}

    @events.unsubscribe(:after_call, unknown_handler)
    @events.notify(:after_call)

    assert_was_called
  end

  def test_unsubscribe_during_notify_does_not_affect_the_in_progress_pass
    b_called = false
    b_handler = nil
    @events.subscribe(:concurrent_event) { @events.unsubscribe(:concurrent_event, b_handler) }
    b_handler = @events.subscribe(:concurrent_event) { b_called = true }

    @events.notify(:concurrent_event)

    assert b_called, 'expected b_handler to still run in the pass that unsubscribed it'
    refute_includes @events.instance_variable_get(:@events)[:concurrent_event], b_handler
  end
end
