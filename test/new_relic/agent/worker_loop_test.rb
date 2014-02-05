# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class NewRelic::Agent::WorkerLoopTest < Minitest::Test
  def setup
    @worker_loop = NewRelic::Agent::WorkerLoop.new
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
    freeze_time

    period = 5.0
    worker_loop = NewRelic::Agent::WorkerLoop.new(:duration => 16.0)

    def worker_loop.sleep(duration)
      advance_time(duration)
    end

    count = 0
    worker_loop.run(period) { count += 1 }
    assert_equal 3, count
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

  def test_task_error__exception
    expects_logging(:error, any_parameters)
    @worker_loop.run(0) do
      @worker_loop.stop
      raise NewRelic::TestHelper::Exception::TestError, "oops"
    end
  end

  def test_worker_loop_propagates_errors_given_the_option
    @worker_loop = NewRelic::Agent::WorkerLoop.new(
      :limit => 2,
      :propagate_errors => true
    )

    assert_raises NewRelic::TestHelpers::Exceptions::TestError do
      @worker_loop.run(0) do
        raise NewRelic::TestHelpers::Exceptions::TestError
      end
    end
  end

  def test_dynamically_adjusts_the_period_once_the_loop_has_been_started
    freeze_time

    worker_loop = NewRelic::Agent::WorkerLoop.new(:limit => 2)

    worker_loop.expects(:sleep).with(5.0)
    worker_loop.expects(:sleep).with(7.0)
    worker_loop.run(5.0) { advance_time(5.0); worker_loop.period = 7.0 }
  end

  def ticks(start, finish, step)
    (start..finish).step(step).map{|i| Time.at(i)}
  end
end
