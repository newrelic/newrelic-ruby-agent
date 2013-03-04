# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

ENV['SKIP_RAILS'] = 'true'
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class NewRelic::Agent::WorkerLoopTest < Test::Unit::TestCase
  def setup
    @worker_loop = NewRelic::Agent::WorkerLoop.new
    @test_start_time = Time.now
  end

  def test_add_task
    @x = false
    @worker_loop.run(0) do
      @worker_loop.stop
      @x = true
    end
    assert @x
  end

  def test_with_duration
    worker_loop = NewRelic::Agent::WorkerLoop.new(:duration => 0.1)

    # Advance in small increments vs our period so time will pass over the
    # nasty multiple calls to Time.now that WorkerLoop makes
    Time.stubs(:now).returns(*ticks(0, 0.12, 0.005))

    count = 0
    worker_loop.run(0.04) do
      count += 1
    end

    assert_equal 2, count
  end

  def test_duration_clock_starts_with_run
    # This test is a little on the nose, but any timing based test WILL fail in CI
    worker_loop = NewRelic::Agent::WorkerLoop.new(:duration => 0.01)
    assert_nil worker_loop.instance_variable_get(:@deadline)

    worker_loop.run(0.001) {}
    assert !worker_loop.instance_variable_get(:@deadline).nil?
  end

  def test_loop_limit
    worker_loop = NewRelic::Agent::WorkerLoop.new(:limit => 2)
    iterations = 0
    worker_loop.run(0) { iterations += 1 }
    assert_equal 2, iterations
  end

  def test_task_error__standard
    expects_logging(:error, any_parameters)
    # This loop task will run twice
    done = false
    @worker_loop.run(0) do
      @worker_loop.stop
      done = true
      raise "Standard Error Test"
    end
    assert done
  end

  class BadBoy < StandardError; end

  def test_task_error__exception
    expects_logging(:error, any_parameters)
    @worker_loop.run(0) do
      @worker_loop.stop
      raise BadBoy, "oops"
    end
  end

  def test_task_error__server
    expects_no_logging(:error)
    expects_logging(:debug, any_parameters)
    @worker_loop.run(0) do
      @worker_loop.stop
      raise NewRelic::Agent::ServerError, "Runtime Error Test"
    end
  end

  def ticks(start, finish, step)
    (start..finish).step(step).map{|i| Time.at(i)}
  end
end
