# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'base64'
require 'thread'
require 'timeout'
require 'zlib'
require 'new_relic/agent/threading/threaded_test_case'
require 'new_relic/agent/thread_profiler'

START_ARGS = {
  "profile_id" => 42,
  "sample_period" => 0.02,
  "duration" => 0.025,
  "only_runnable_threads" => false,
  "only_request_threads" => false,
  "profile_agent_code" => false,
}
STOP_ARGS = {
  "profile_id" => 42,
  "report_data" => true,
}

STOP_AND_DISCARD_ARGS = {
  "profile_id" => 42,
  "report_data" => false,
}

if !NewRelic::Agent::ThreadProfiler.is_supported?

class ThreadProfilerUnsupportedTest < Test::Unit::TestCase
  def setup
    @profiler = NewRelic::Agent::ThreadProfiler.new
  end

  def test_thread_profiling_isnt_supported
    assert_equal false, NewRelic::Agent::ThreadProfiler.is_supported?
  end

  def test_wont_start_when_not_supported
    @profiler.start(START_ARGS)
    assert_equal false, @profiler.running?
  end

  def test_stop_is_safe_when_not_supported
    @profiler.start(START_ARGS)
    @profiler.stop(true)
  end

  def test_wont_start_and_reports_error
    errors = nil
    @profiler.handle_start_command(START_ARGS) do |_, err|
      errors = err
    end
    assert_equal false, errors.nil?
    assert_equal false, @profiler.running?
  end

end

else

require 'json'

class ThreadProfilerTest < ThreadedTestCase
  def setup
    super
    @profiler = NewRelic::Agent::ThreadProfiler.new
  end

  def test_is_supported
    assert NewRelic::Agent::ThreadProfiler.is_supported?
  end

  def test_is_not_running
    assert !@profiler.running?
  end

  def test_is_running
    @profiler.start(START_ARGS)
    assert @profiler.running?
  end

  def test_is_not_finished_if_no_profile_started
    assert !@profiler.finished?
  end

  def test_can_stop_a_running_profile
    @profiler.start(START_ARGS)
    assert @profiler.running?

    @profiler.stop(true)

    assert @profiler.finished?
    assert_not_nil @profiler.harvest
  end

  def test_can_stop_a_running_profile_and_discard
    @profiler.start(START_ARGS)
    assert @profiler.running?

    @profiler.stop(false)

    assert_nil @profiler.harvest
  end

  def test_wont_crash_if_stopping_when_not_started
    @profiler.stop(true)
    assert_equal false, @profiler.running?
  end

  def test_handle_start_command_starts_running
    @profiler.handle_start_command(START_ARGS)
    assert_equal true, @profiler.running?
  end

  def test_handle_stop_command
    @profiler.start(START_ARGS)
    assert @profiler.running?

    @profiler.handle_stop_command(STOP_ARGS)
    assert_equal true, @profiler.finished?
  end

  def test_handle_stop_command_and_discard
    @profiler.start(START_ARGS)
    assert @profiler.running?

    @profiler.handle_stop_command(STOP_AND_DISCARD_ARGS)
    assert_nil @profiler.harvest
  end

  def test_handle_start_command_wont_start_second_profile
    @profiler.handle_start_command(START_ARGS)
    original_profile = @profiler.instance_variable_get(:@profile)

    begin
      @profiler.handle_start_command(START_ARGS)
    rescue NewRelic::Agent::AgentCommandRouter::AgentCommandError
    end

    assert_equal original_profile, @profiler.harvest
  end

  def test_start_command_sent_twice_raises_error
    @profiler.handle_start_command(START_ARGS)

    assert_raise NewRelic::Agent::AgentCommandRouter::AgentCommandError do
      @profiler.handle_start_command(START_ARGS)
    end
  end

  def test_command_attributes_passed_along
    @profiler.handle_start_command(START_ARGS)
    profile = @profiler.harvest
    assert_equal 42,  profile.profile_id
    assert_equal 0.02, profile.interval
    assert_equal false, profile.profile_agent_code
  end

end

end
