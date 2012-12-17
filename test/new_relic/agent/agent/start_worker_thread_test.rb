require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
class NewRelic::Agent::Agent::StartWorkerThreadTest < Test::Unit::TestCase
  require 'new_relic/agent/agent'
  include NewRelic::Agent::Agent::StartWorkerThread

  def test_deferred_work_connects
    self.expects(:catch_errors).yields
    self.expects(:connect).with('connection_options')
    @connected = true
    self.expects(:log_worker_loop_start)
    self.expects(:create_and_run_worker_loop)
    deferred_work!('connection_options')
  end

  def test_deferred_work_connect_failed
    self.expects(:catch_errors).yields
    self.expects(:connect).with('connection_options')
    @connected = false
    ::NewRelic::Agent.logger.expects(:debug).with("No connection.  Worker thread ending.")
    deferred_work!('connection_options')
  end

  def test_log_worker_loop_start
    ::NewRelic::Agent.logger.expects(:info).with("Reporting performance data every 30 seconds.")
    ::NewRelic::Agent.logger.expects(:debug).with("Running worker loop")
    with_config(:data_report_period => 30) do
      log_worker_loop_start
    end
  end

  def test_create_and_run_worker_loop
    @should_send_samples = true
    wl = mock('worker loop')
    NewRelic::Agent::WorkerLoop.expects(:new).returns(wl)
    wl.expects(:run).with(30).yields
    self.expects(:transmit_data)
    with_config(:data_report_period => 30) do
      create_and_run_worker_loop
    end
  end

  def test_handle_force_restart
    # hooray for methods with no branches
    error = mock(:message => 'a message')
    ::NewRelic::Agent.logger.expects(:info).with('a message')

    self.expects(:reset_stats)
    self.expects(:sleep).with(30)

    @metric_ids = 'this is not an empty hash'
    @connected = true

    handle_force_restart(error)

    assert_equal({}, @metric_ids)
    assert @connected.nil?
  end

  def test_handle_force_disconnect
    error = mock(:message => 'a message')
    ::NewRelic::Agent.logger.expects(:error).with("New Relic forced this agent to disconnect (a message)")

    self.expects(:disconnect)
    handle_force_disconnect(error)
  end

  def test_handle_server_connection_problem
    error = StandardError.new('a message')

    ::NewRelic::Agent.logger.expects(:error).with( \
      includes('Unable to establish connection with the server.'),
      instance_of(StandardError))

    self.expects(:disconnect)
    handle_server_connection_problem(error)
  end

  def test_handle_other_error
    error = StandardError.new('a message')

    ::NewRelic::Agent.logger.expects(:error).with( \
      includes("Terminating worker loop"), \
      instance_of(StandardError))

    self.expects(:disconnect)
    handle_other_error(error)
  end

  def test_catch_errors_force_restart
    @runs = 0
    error = NewRelic::Agent::ForceRestartException.new
    # twice, because we expect it to retry the block
    self.expects(:handle_force_restart).with(error).twice
    catch_errors do
      # needed to keep it from looping infinitely in the test
      @runs += 1
      raise error unless @runs > 2
    end
    assert_equal 3, @runs, 'should retry the block when it fails'
  end

  private

  def mocked_control
    fake_control = mock('control')
    self.stubs(:control).returns(fake_control)
    fake_control
  end
end

