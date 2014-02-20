# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class EventListenerTest < Minitest::Test

  def setup
    @events = NewRelic::Agent::EventListener.new

    @called = false
    @called_with = nil

    @check_method = Proc.new do |*args|
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
    assert !@called, "Event was called"
  end


  #
  # Tests
  #

  def test_notifies
    @events.subscribe(:before_call, &@check_method)
    @events.notify(:before_call, :env => "env")

    assert_was_called
    assert_equal([{:env => "env"}], @called_with)
  end

  def test_failure_during_notify_doesnt_block_other_hooks
    @events.subscribe(:after_call) { raise "Boo!" }
    @events.subscribe(:after_call, &@check_method)

    @events.notify(:after_call)

    assert_was_called
  end

  def test_runaway_events
    @events.runaway_threshold = 0
    expects_logging(:debug, includes("my_event"))
    @events.subscribe(:my_event) {}
  end

  def test_clear
    @events.subscribe(:after_call, &@check_method)
    @events.clear
    @events.notify(:after_call)

    assert_was_not_called
  end

end
