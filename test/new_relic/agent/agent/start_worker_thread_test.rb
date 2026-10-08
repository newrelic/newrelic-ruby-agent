# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'

class NewRelic::Agent::Agent::StartWorkerThreadTest < Minitest::Test
  require 'new_relic/agent/agent'
  include NewRelic::Agent::AgentHelpers::StartWorkerThread

  def test_deferred_work_connects
    self.expects(:catch_errors).yields
    self.expects(:connect).with('connection_options')
    NewRelic::Agent.instance.stubs(:connected?).returns(true)
    self.stubs(:transmit_agent_settings)
    self.expects(:create_and_run_event_loop)
    deferred_work!('connection_options')
  end

  def test_deferred_work_connect_failed
    self.expects(:catch_errors).yields
    self.expects(:connect).with('connection_options')
    NewRelic::Agent.instance.stubs(:connected?).returns(false)
    self.expects(:transmit_agent_settings).never
    deferred_work!('connection_options')
  end

  def test_deferred_work_transmits_agent_settings_before_event_loop
    self.expects(:catch_errors).yields
    self.stubs(:connect)
    NewRelic::Agent.instance.stubs(:connected?).returns(true)
    sequence = sequence('deferred_work')
    self.expects(:transmit_agent_settings).once.in_sequence(sequence)
    self.expects(:create_and_run_event_loop).in_sequence(sequence)
    deferred_work!('connection_options')
  end

  def test_deferred_work_does_not_transmit_agent_settings_when_disabled
    self.expects(:catch_errors).yields
    self.stubs(:connect)
    NewRelic::Agent.instance.stubs(:connected?).returns(true)
    self.expects(:transmit_agent_settings).never
    self.stubs(:create_and_run_event_loop)
    with_config(:enable_agent_settings => false) do
      deferred_work!('connection_options')
    end
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
