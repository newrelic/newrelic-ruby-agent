# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
class NewRelic::Agent::Agent::StartWorkerThreadTest < Minitest::Test
  require 'new_relic/agent/agent'
  include NewRelic::Agent::Agent::StartWorkerThread

  def test_deferred_work_connects
    self.expects(:catch_errors).yields
    self.expects(:connect).with('connection_options')
    self.stubs(:connected?).returns(true)
    self.expects(:create_and_run_event_loop)
    deferred_work!('connection_options')
  end

  def test_deferred_work_connect_failed
    self.expects(:catch_errors).yields
    self.expects(:connect).with('connection_options')
    self.stubs(:connected?).returns(false)
    deferred_work!('connection_options')
  end

  def test_handle_force_restart
    # hooray for methods with no branches
    error = mock(:message => 'a message')

    self.expects(:drop_buffered_data)
    self.expects(:sleep).with(30)

    @connected = true
    @service = mock('service', :force_restart => nil)

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
