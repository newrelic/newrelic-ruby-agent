# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
class NewRelic::Agent::Agent::StartWorkerThreadTest < Test::Unit::TestCase
  require 'new_relic/agent/agent'
  include NewRelic::Agent::Agent::StartWorkerThread

  def test_deferred_work_connects
    self.expects(:catch_errors).yields
    self.expects(:connect).with('connection_options')
    self.stubs(:connected?).returns(true)
    self.expects(:log_worker_loop_start)
    self.expects(:create_and_run_worker_loop)
    deferred_work!('connection_options')
  end

  def test_deferred_work_connect_failed
    self.expects(:catch_errors).yields
    self.expects(:connect).with('connection_options')
    self.stubs(:connected?).returns(false)
    deferred_work!('connection_options')
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

    self.expects(:reset_stats)
    self.expects(:sleep).with(30)
    @connected = true

    handle_force_restart(error)

    assert_equal(:pending, @connect_state)
  end

  def test_handle_force_disconnect
    error = mock(:message => 'a message')

    self.expects(:disconnect)
    handle_force_disconnect(error)
  end

  def test_handle_other_error
    error = StandardError.new('a message')

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
