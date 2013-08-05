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

COMMAND_ID = 666

START_NAME = "start_profiler"
START_ARGS = {
  "profile_id" => 42,
  "sample_period" => 0.02,
  "duration" => 0.025,
  "only_runnable_threads" => false,
  "only_request_threads" => false,
  "profile_agent_code" => false,
}

STOP_NAME = "stop_profiler"
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
    @profiler.start(0, 0, 0, true)
    assert_equal false, @profiler.running?
  end

  def test_stop_is_safe_when_not_supported
    @profiler.start(0, 0, 0, true)
    @profiler.stop(true)
  end

  def test_wont_start_and_reports_error
    errors = nil
    @profiler.respond_to_start(COMMAND_ID, START_NAME, START_ARGS) do |_, err|
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
    @profiler.start(0, 0, 0, true)
    assert @profiler.running?
  end

  def test_is_not_finished_if_no_profile_started
    assert !@profiler.finished?
  end

  def test_can_stop_a_running_profile
    @profiler.start(0, 0, 0, true)
    assert @profiler.running?

    @profiler.stop(true)

    assert @profiler.finished?
    assert_not_nil @profiler.profile
  end

  def test_can_stop_a_running_profile_and_discard
    @profiler.start(0, 0, 0, true)
    assert @profiler.running?

    @profiler.stop(false)

    assert_nil @profiler.profile
  end

  def test_wont_crash_if_stopping_when_not_started
    @profiler.stop(true)
    assert_equal false, @profiler.running?
  end

  def test_respond_to_start_starts_running
    @profiler.respond_to_start(COMMAND_ID, START_NAME, START_ARGS)
    assert_equal true, @profiler.running?
  end

  def test_respond_to_stop
    @profiler.start(0, 0, 0, true)
    assert @profiler.running?

    @profiler.respond_to_stop(COMMAND_ID, STOP_NAME, STOP_ARGS)
    assert_equal true, @profiler.profile.finished?
  end

  def test_respond_to_stop_and_discard
    @profiler.start(0, 0, 0, true)
    assert @profiler.running?

    @profiler.respond_to_stop(COMMAND_ID, STOP_NAME, STOP_AND_DISCARD_ARGS)
    assert_nil @profiler.profile
  end

  def test_respond_to_start_wont_start_second_profile
    @profiler.start(0, 0, 0, true)
    original_profile = @profiler.profile

    @profiler.respond_to_start(COMMAND_ID, START_NAME, START_ARGS)

    assert_equal original_profile, @profiler.profile
  end

  def test_response_to_commands_start_notifies_of_result
    saw_command_id = nil
    @profiler.respond_to_start(COMMAND_ID, START_NAME, START_ARGS) do |id, _|
      saw_command_id = id
    end

    assert_equal 666, saw_command_id
  end

  def test_response_to_commands_start_notifies_of_error
    saw_command_id = nil
    error = nil

    @profiler.respond_to_start(COMMAND_ID, START_NAME, START_ARGS)
    @profiler.respond_to_start(COMMAND_ID, START_NAME, START_ARGS) do |id, err|
      saw_command_id = id
      error = err
    end

    assert_equal 666, saw_command_id
    assert_not_nil error
  end

  def test_response_to_commands_stop_notifies_of_result
    saw_command_id = nil
    @profiler.start(0,0, 0, true)
    @profiler.respond_to_stop(COMMAND_ID, STOP_NAME, STOP_ARGS) do |id, _|
      saw_command_id = id
    end
    assert_equal 666, saw_command_id
  end

  def test_command_attributes_passed_along
    @profiler.respond_to_start(COMMAND_ID, START_NAME, START_ARGS)
    assert_equal 42,  @profiler.profile.profile_id
    assert_equal 0.02, @profiler.profile.interval
    assert_equal false, @profiler.profile.profile_agent_code
  end

end

end
