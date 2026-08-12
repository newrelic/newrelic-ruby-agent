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

  def test_unsubscribe_is_a_no_op_for_an_unknown_handler
    @events.unsubscribe(:after_call, @check_method)
    @events.notify(:after_call)

    assert_was_not_called
  end
end
