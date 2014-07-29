# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class NewRelic::Agent::EventLoopTest < Minitest::Test
  def setup
    @loop = NewRelic::Agent::EventLoop.new
  end

  def test_fire_after
    freeze_time
    call_count = 0

    @loop.on(:event) { call_count += 1 }
    @loop.fire_after(3, :event)

    @loop.run_once(true)
    assert_equal(0, call_count)

    advance_time(1)
    @loop.run_once(true)
    assert_equal(0, call_count)

    advance_time(2)
    @loop.run_once(true)
    assert_equal(1, call_count)

    advance_time(5)
    @loop.run_once(true)
    assert_equal(1, call_count)
  end

  def test_fire_every
    freeze_time
    call_count = 0

    @loop.on(:event) do
      call_count += 1
    end

    @loop.fire_every(3, :event)

    @loop.run_once(true)
    assert_equal(0, call_count)

    advance_time(2)
    @loop.run_once(true)
    assert_equal(0, call_count)

    advance_time(1)
    @loop.run_once(true)
    assert_equal(1, call_count)

    advance_time(4)
    @loop.run_once(true)
    assert_equal(2, call_count)
  end

  def test_fire_resets_associated_timers
    freeze_time
    call_count = 0

    @loop.on(:event) { call_count += 1 }
    @loop.fire_every(10, :event)

    advance_time(5)
    @loop.fire(:event)
    @loop.run_once(true)
    assert_equal(1, call_count)

    advance_time(5)
    @loop.run_once(true)
    assert_equal(1, call_count)

    advance_time(5)
    @loop.run_once(true)
    assert_equal(2, call_count)
  end

  def test_adjust_period_larger
    freeze_time

    call_count = 0
    @loop.on(:e) { call_count += 1 }

    @loop.fire_every(10, :e)
    @loop.run_once(true)

    advance_time(9)
    @loop.run_once(true)
    assert_equal(0, call_count)

    advance_time(1)
    @loop.fire_every(15, :e)
    @loop.run_once(true)
    assert_equal(0, call_count)

    advance_time(5)
    @loop.run_once(true)
    assert_equal(1, call_count)
  end

  def test_adjust_period_smaller
    freeze_time

    call_count = 0
    @loop.on(:e) { call_count += 1 }
    @loop.fire_every(10, :e)

    @loop.run_once(true)
    assert_equal(0, call_count)

    advance_time(5)
    @loop.run_once(true)
    assert_equal(0, call_count)

    @loop.fire_every(2, :e)
    @loop.run_once(true)
    assert_equal(1, call_count)

    advance_time(1)
    @loop.run_once(true)
    assert_equal(1, call_count)

    advance_time(1)
    @loop.run_once(true)
    assert_equal(2, call_count)
  end

  def test_on
    call_count = 0
    @loop.on(:evt) do
      call_count += 1
    end
    @loop.fire(:evt)
    @loop.run_once(true)
    assert_equal(1, call_count)
  end

  def test_on_with_payload
    call_count = 0
    @loop.on(:evt) do |amount|
      call_count += amount
    end
    @loop.fire(:evt, 42)
    @loop.run_once(true)
    assert_equal(42, call_count)
  end

  def test_manual_fire_resets_timers
    freeze_time

    call_count = 0
    @loop.on(:e) { call_count += 1 }
    @loop.fire_every(4, :e)

    advance_time(3)
    @loop.run_once(true)
    assert_equal(0, call_count)

    @loop.fire(:e)
    @loop.run_once(true)
    assert_equal(1, call_count)

    advance_time(3)
    @loop.run_once(true)
    assert_equal(1, call_count)

    advance_time(1)
    @loop.run_once(true)
    assert_equal(2, call_count)
  end

  def test_exceptions_do_not_exit_loop
    call_count = 0
    @loop.on(:e) { raise StandardError.new }
    @loop.on(:e) { call_count += 1 }
    @loop.on(:e) { raise StandardError.new }

    @loop.fire(:e)

    @loop.run_once(true)
    assert_equal(1, call_count)
  end
end
