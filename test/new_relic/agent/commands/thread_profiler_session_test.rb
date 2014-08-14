# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'base64'
require 'thread'
require 'timeout'
require 'zlib'
require 'new_relic/agent/threading/backtrace_service'
require 'new_relic/agent/threading/threaded_test_case'
require 'new_relic/agent/commands/thread_profiler_session'

module ThreadProfilerSessionTestHelpers
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

if !NewRelic::Agent::Threading::BacktraceService.is_supported?

  class ThreadProfilerUnsupportedTest < Minitest::Test
    include ThreadProfilerSessionTestHelpers

    def setup
      backtrace_service = NewRelic::Agent::Threading::BacktraceService.new
      @profiler = NewRelic::Agent::Commands::ThreadProfilerSession.new(backtrace_service)
    end

    def test_thread_profiling_isnt_supported
      assert_equal false, NewRelic::Agent::Threading::BacktraceService.is_supported?
    end

    def test_stop_is_safe_when_not_supported
      @profiler.start(start_command)
      @profiler.stop(true)
    end

    def test_wont_start_and_reports_error
      assert_raises NewRelic::Agent::Commands::AgentCommandRouter::AgentCommandError do
        @profiler.handle_start_command(start_command)
      end
      assert_equal false, @profiler.running?
    end

  end

else

  require 'json'

  class ThreadProfilerSessionTest < Minitest::Test
    include ThreadedTestCase
    include ThreadProfilerSessionTestHelpers

    def setup
      setup_fake_threads
      backtrace_service = NewRelic::Agent::Threading::BacktraceService.new
      backtrace_service.worker_loop.stubs(:run).returns(nil)
      @profiler = NewRelic::Agent::Commands::ThreadProfilerSession.new(backtrace_service)
    end

    def teardown
      NewRelic::Agent.instance.stats_engine.clear_stats
      teardown_fake_threads
    end

    def test_is_supported
      assert NewRelic::Agent::Threading::BacktraceService.is_supported?
    end

    def test_is_not_running
      assert_false @profiler.running?
    end

    def test_is_running
      @profiler.start(start_command)
      assert @profiler.running?
    end

    def test_is_not_ready_to_harvest_if_no_profile_started
      assert_false @profiler.ready_to_harvest?
    end

    def test_is_ready_to_harvest_if_duration_has_elapsed
      freeze_time
      @profiler.start(start_command)
      assert_false @profiler.ready_to_harvest?

      advance_time(0.026)
      assert @profiler.ready_to_harvest?
    end

    def test_can_stop_a_running_profile
      @profiler.start(start_command)
      assert @profiler.running?

      @profiler.stop(true)
      assert_false @profiler.running?

      refute_nil @profiler.harvest
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

    def test_config_can_disable_running
      with_config(:'thread_profiler.enabled' => false) do
        assert_raises NewRelic::Agent::Commands::AgentCommandRouter::AgentCommandError do
          @profiler.handle_start_command(start_command)
        end
        assert_false @profiler.running?
      end
    end

    def test_handle_stop_command
      @profiler.start(start_command)
      assert @profiler.running?

      @profiler.handle_stop_command(stop_command)
      assert_false @profiler.running?
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

      assert_raises NewRelic::Agent::Commands::AgentCommandRouter::AgentCommandError do
        @profiler.handle_start_command(start_command)
      end
    end

    def test_harvested_profile_doesnt_still_report_as_ready_to_harvest
      freeze_time
      @profiler.handle_start_command(start_command)

      advance_time(1.0)
      @profiler.stop(true)
      assert @profiler.ready_to_harvest?

      @profiler.harvest
      assert_false @profiler.ready_to_harvest?
    end

    def test_command_attributes_passed_along
      @profiler.handle_start_command(start_command)
      @profiler.handle_stop_command(stop_command)
      profile = @profiler.harvest
      assert_equal 42,  profile.profile_id
      assert_equal 0.02, profile.requested_period
    end

  end
end
