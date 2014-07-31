# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class NewRelic::Agent::EventLoopTest < Minitest::Test
  def setup
    freeze_time
    @loop = NewRelic::Agent::EventLoop.new
  end

  def test_fire_after
    call_count = 0

    @loop.on(:event) { call_count += 1 }
    @loop.fire_after(3, :event)

    @loop.run_once(true)
    assert_equal(0, call_count)

    advance_loop(1)
    assert_equal(0, call_count)

    advance_loop(2)
    assert_equal(1, call_count)

    advance_loop(5)
    assert_equal(1, call_count)
  end

  def test_fire_every
    call_count = 0

    @loop.on(:event) do
      call_count += 1
    end

    @loop.fire_every(3, :event)

    @loop.run_once(true)
    assert_equal(0, call_count)

    advance_loop(2)
    assert_equal(0, call_count)

    advance_loop(1)
    assert_equal(1, call_count)

    advance_loop(4)
    assert_equal(2, call_count)
  end

  def test_fire_resets_associated_timers
    call_count = 0

    @loop.on(:event) { call_count += 1 }
    @loop.fire_every(10, :event)

    advance_loop(5)
    @loop.fire(:event)
    @loop.run_once(true)
    assert_equal(1, call_count)

    advance_loop(5)
    assert_equal(1, call_count)

    advance_loop(5)
    assert_equal(2, call_count)
  end

  def test_adjust_period_larger
    call_count = 0
    @loop.on(:e) { call_count += 1 }

    @loop.fire_every(10, :e)
    @loop.run_once(true)

    advance_loop(9)
    assert_equal(0, call_count)

    @loop.fire_every(15, :e)
    @loop.run_once(true)
    assert_equal(0, call_count)

    advance_loop(1)
    assert_equal(0, call_count)

    advance_loop(5)
    assert_equal(1, call_count)
  end

  def test_adjust_period_smaller
    call_count = 0
    @loop.on(:e) { call_count += 1 }
    @loop.fire_every(10, :e)

    @loop.run_once(true)
    assert_equal(0, call_count)

    advance_loop(5)
    assert_equal(0, call_count)

    @loop.fire_every(2, :e)
    @loop.run_once(true)
    assert_equal(1, call_count)

    advance_loop(1)
    assert_equal(1, call_count)

    advance_loop(1)
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
    call_count = 0
    @loop.on(:e) { call_count += 1 }
    @loop.fire_every(4, :e)

    advance_loop(3)
    assert_equal(0, call_count)

    @loop.fire(:e)
    @loop.run_once(true)
    assert_equal(1, call_count)

    advance_loop(3)
    assert_equal(1, call_count)

    advance_loop(1)
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

  def test_timer_period_reset_from_event
    call_count = 0
    @loop.on(:e           ) { call_count += 1          }
    @loop.on(:reset_period) { @loop.fire_every(30, :e) }

    @loop.fire_every( 5, :e           )
    @loop.fire_after(31, :reset_period)

    advance_loop(3)  # total time 3
    assert_equal(0, call_count)

    advance_loop(2)  # total time 5
    assert_equal(1, call_count)

    advance_loop(5)  # total time 10
    assert_equal(2, call_count)

    advance_loop(20)  # total time 30
    assert_equal(6, call_count)

    advance_loop(29)  # total time 59
    assert_equal(6, call_count)

    advance_loop(1)  # total time 60
    assert_equal(7, call_count)

    advance_loop(60)  # total time 120
    assert_equal(9, call_count)
  end

  def advance_loop(n)
    n.times do
      advance_time(1)
      @loop.run_once(true)
    end
  end
end
