# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'base64'
require 'thread'
require 'timeout'
require 'zlib'
require 'new_relic/agent/threading/threaded_test_case'
require 'new_relic/agent/commands/thread_profiler'
#require 'test/new_relic/agent/commands/agent_command_test'

module ThreadProfilerTestHelpers
  START = {
    "profile_id" => 42,
    "sample_period" => 0.02,
    "duration" => 0.025,
    "only_runnable_threads" => false,
    "only_request_threads" => false,
    "profile_agent_code" => false,
  }
  STOP = {
    "profile_id" => 42,
    "report_data" => true,
  }

  STOP_AND_DISCARD = {
    "profile_id" => 42,
    "report_data" => false,
  }

  def start_command
    create_agent_command(START)
  end

  def stop_command
    create_agent_command(STOP)
  end

  def stop_and_discard_command
    create_agent_command(STOP_AND_DISCARD)
  end
end

if !NewRelic::Agent::Commands::ThreadProfiler.is_supported?

  class ThreadProfilerUnsupportedTest < Test::Unit::TestCase
    include ThreadProfilerTestHelpers

    def setup
      @profiler = NewRelic::Agent::Commands::ThreadProfiler.new
    end

    def test_thread_profiling_isnt_supported
      assert_equal false, NewRelic::Agent::Commands::ThreadProfiler.is_supported?
    end

    def test_stop_is_safe_when_not_supported
      @profiler.start(start_command)
      @profiler.stop(true)
    end

    def test_wont_start_and_reports_error
      errors = nil
      assert_raise NewRelic::Agent::Commands::AgentCommandRouter::AgentCommandError do
        @profiler.handle_start_command(start_command)
      end
      assert_equal false, @profiler.running?
    end

  end

else

  require 'json'

  class ThreadProfilerTest < ThreadedTestCase
    include ThreadProfilerTestHelpers

    def setup
      super
      @profiler = NewRelic::Agent::Commands::ThreadProfiler.new
    end

    def test_is_supported
      assert NewRelic::Agent::Commands::ThreadProfiler.is_supported?
    end

    def test_is_not_running
      assert !@profiler.running?
    end

    def test_is_running
      @profiler.start(start_command)
      assert @profiler.running?
    end

    def test_is_not_finished_if_no_profile_started
      assert !@profiler.finished?
    end

    def test_can_stop_a_running_profile
      @profiler.start(start_command)
      assert @profiler.running?

      @profiler.stop(true)

      assert @profiler.finished?
      assert_not_nil @profiler.harvest
    end

    def test_can_stop_a_running_profile_and_discard
      @profiler.start(start_command)
      assert @profiler.running?

      @profiler.stop(false)

      assert_nil @profiler.harvest
    end

    def test_wont_crash_if_stopping_when_not_started
      @profiler.stop(true)
      assert_equal false, @profiler.running?
    end

    def test_handle_start_command_starts_running
      @profiler.handle_start_command(start_command)
      assert_equal true, @profiler.running?
    end

    def test_handle_stop_command
      @profiler.start(start_command)
      assert @profiler.running?

      @profiler.handle_stop_command(stop_command)
      assert_equal true, @profiler.finished?
    end

    def test_handle_stop_command_and_discard
      @profiler.start(start_command)
      assert @profiler.running?

      @profiler.handle_stop_command(stop_and_discard_command)
      assert_nil @profiler.harvest
    end

    def test_handle_start_command_wont_start_second_profile
      @profiler.handle_start_command(start_command)
      original_profile = @profiler.instance_variable_get(:@profile)

      begin
        @profiler.handle_start_command(start_command)
      rescue NewRelic::Agent::Commands::AgentCommandRouter::AgentCommandError
      end

      assert_equal original_profile, @profiler.harvest
    end

    def test_start_command_sent_twice_raises_error
      @profiler.handle_start_command(start_command)

      assert_raise NewRelic::Agent::Commands::AgentCommandRouter::AgentCommandError do
        @profiler.handle_start_command(start_command)
      end
    end

    def test_command_attributes_passed_along
      @profiler.handle_start_command(start_command)
      profile = @profiler.harvest
      assert_equal 42,  profile.profile_id
      assert_equal 0.02, profile.interval
      assert_equal false, profile.profile_agent_code
    end

  end
end
