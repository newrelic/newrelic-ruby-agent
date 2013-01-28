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
    count = 0
    worker_loop.run(0.04) do
      count += 1
    end

    assert_equal 2, count
  end

  def test_loop_limit
    worker_loop = NewRelic::Agent::WorkerLoop.new(:limit => 2)
    iterations = 0
    worker_loop.run(0) { iterations += 1 }
    assert_equal 2, iterations
  end

  def test_density
    # This shows how the tasks stay aligned with the period and don't drift.
    count = 0
    start = Time.now
    @worker_loop.run(0.03) do
      count +=1
      if count == 3
        @worker_loop.stop
        next
      end
    end
    elapsed = Time.now - start
    assert_in_delta 0.09, elapsed, 0.03
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
    expects_no_logging(:error, any_parameters)
    expects_logging(:debug, any_parameters)
    @worker_loop.run(0) do
      @worker_loop.stop
      raise NewRelic::Agent::ServerError, "Runtime Error Test"
    end
  end
end
