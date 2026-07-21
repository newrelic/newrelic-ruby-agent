# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/continuous_profiling/session'

module NewRelic::Agent::ContinuousProfiling
  class SessionTest < Minitest::Test
    def setup
      @events = NewRelic::Agent::EventListener.new
      @session = Session.new(@events)
      @fake_thread = stub_everything('fake continuous profiling thread')
      NewRelic::Agent::Threading::AgentThread.stubs(:create).returns(@fake_thread)
      NewRelic::Agent::ContinuousProfiling::StackProfSampler.any_instance.stubs(:start)
    end

    def test_maybe_start_does_nothing_when_disabled
      with_config(:'continuous_profiler.enabled' => false) do
        @session.expects(:start).never
        @session.maybe_start
      end
    end

    def test_maybe_start_does_nothing_on_jruby
      with_config(:'continuous_profiler.enabled' => true) do
        NewRelic::LanguageSupport.stub :jruby?, true do
          @session.expects(:start).never
          @session.maybe_start
        end
      end
    end

    def test_maybe_start_starts_when_enabled_and_supported
      @session.stubs(:gems_present?).returns(true)

      with_config(:'continuous_profiler.enabled' => true) do
        NewRelic::LanguageSupport.stub :jruby?, false do
          @session.expects(:start)
          @session.maybe_start
        end
      end
    end

    def test_maybe_start_does_nothing_when_gems_missing
      @session.stubs(:gems_present?).returns(false)

      with_config(:'continuous_profiler.enabled' => true) do
        NewRelic::LanguageSupport.stub :jruby?, false do
          @session.expects(:start).never
          @session.maybe_start
        end
      end
    end

    def test_start_starts_the_sampler_and_creates_a_thread
      NewRelic::Agent::ContinuousProfiling::StackProfSampler.any_instance.expects(:start)
      NewRelic::Agent::Threading::AgentThread.expects(:create).with('Continuous Profiling').returns(@fake_thread)

      @session.start

      assert_predicate @session, :running?
      assert_metrics_recorded('Supportability/Ruby/Profiling/Enabled')
    end

    def test_start_is_idempotent
      NewRelic::Agent::ContinuousProfiling::StackProfSampler.any_instance.expects(:start).once
      NewRelic::Agent::Threading::AgentThread.expects(:create).once.returns(@fake_thread)

      @session.start
      @session.start

      assert_predicate @session, :running?
    end

    def test_stop_flips_running_and_joins_the_thread
      @fake_thread.expects(:join)
      @session.start

      @session.stop

      refute_predicate @session, :running?
      assert_metrics_recorded('Supportability/Ruby/Profiling/Disabled')
    end

    def test_stop_is_a_no_op_when_not_running
      @fake_thread.expects(:join).never

      @session.stop

      refute_predicate @session, :running?
    end

    def test_harvest_and_send_collects_encodes_exports_and_restarts_the_sampler
      report = {:samples => 3, :mode => :wall}
      sampler = NewRelic::Agent::ContinuousProfiling::StackProfSampler.new
      sampler.expects(:stop_and_collect).returns(report)
      sampler.expects(:start)
      @session.instance_variable_set(:@sampler, sampler)
      @session.instance_variable_set(:@running, true)
      @session.expects(:encode_and_export).with(report)

      @session.send(:harvest_and_send)
    end

    def test_harvest_and_send_restarts_the_sampler_even_when_collection_raises
      sampler = NewRelic::Agent::ContinuousProfiling::StackProfSampler.new
      sampler.expects(:stop_and_collect).raises('boom')
      sampler.expects(:start)
      @session.instance_variable_set(:@sampler, sampler)
      @session.instance_variable_set(:@running, true)

      @session.send(:harvest_and_send)
    end

    def test_harvest_and_send_restarts_the_sampler_even_when_encode_and_export_raises
      report = {:samples => 3, :mode => :wall}
      sampler = NewRelic::Agent::ContinuousProfiling::StackProfSampler.new
      sampler.expects(:stop_and_collect).returns(report)
      sampler.expects(:start)
      @session.instance_variable_set(:@sampler, sampler)
      @session.instance_variable_set(:@running, true)
      @session.stubs(:encode_and_export).raises('boom')

      @session.send(:harvest_and_send)
    end

    def test_server_source_configuration_added_starts_session_when_newly_enabled
      @session.stubs(:gems_present?).returns(true)

      with_config(:'continuous_profiler.enabled' => true) do
        NewRelic::LanguageSupport.stub :jruby?, false do
          @session.expects(:start)
          @events.notify(:server_source_configuration_added)
        end
      end
    end

    def test_server_source_configuration_added_does_not_start_when_gems_missing
      @session.stubs(:gems_present?).returns(false)

      with_config(:'continuous_profiler.enabled' => true) do
        NewRelic::LanguageSupport.stub :jruby?, false do
          @session.expects(:start).never
          @events.notify(:server_source_configuration_added)
        end
      end
    end

    def test_server_source_configuration_added_stops_session_when_newly_disabled
      @session.start

      with_config(:'continuous_profiler.enabled' => false) do
        @session.expects(:stop)
        @events.notify(:server_source_configuration_added)
      end
    end

    def test_start_transaction_restarts_after_fork
      @session.start
      original_thread = @session.instance_variable_get(:@thread)

      real_pid = Process.pid
      Process.stubs(:pid).returns(real_pid + 1)
      NewRelic::Agent::Threading::AgentThread.stubs(:create).returns(stub_everything('post-fork thread'))
      @events.notify(:start_transaction)

      assert_predicate @session, :running?
      refute_equal original_thread, @session.instance_variable_get(:@thread)
    end

    def test_start_transaction_does_not_restart_without_a_fork
      @session.start

      @session.expects(:start).never
      @events.notify(:start_transaction)
    end

    def test_start_transaction_does_not_restart_when_not_running
      @session.expects(:start).never
      real_pid = Process.pid
      Process.stubs(:pid).returns(real_pid + 1)
      @events.notify(:start_transaction)

      refute_predicate @session, :running?
    end

    def test_before_shutdown_stops_the_session
      @session.start

      @session.expects(:stop)
      @events.notify(:before_shutdown)
    end

    def test_handle_start_command_raises_when_gems_missing
      @session.stubs(:gems_present?).returns(false)

      with_config(:'continuous_profiler.enabled' => true) do
        assert_raises NewRelic::Agent::Commands::AgentCommandRouter::AgentCommandError do
          @session.handle_start_command(create_agent_command)
        end
      end

      refute_predicate @session, :running?
    end

    def test_handle_start_command_raises_when_disabled_via_config
      @session.stubs(:gems_present?).returns(true)

      with_config(:'continuous_profiler.enabled' => false) do
        assert_raises NewRelic::Agent::Commands::AgentCommandRouter::AgentCommandError do
          @session.handle_start_command(create_agent_command)
        end
      end

      refute_predicate @session, :running?
    end

    def test_handle_start_command_raises_when_already_running
      @session.stubs(:gems_present?).returns(true)

      with_config(:'continuous_profiler.enabled' => true) do
        @session.start

        assert_raises NewRelic::Agent::Commands::AgentCommandRouter::AgentCommandError do
          @session.handle_start_command(create_agent_command)
        end
      end
    end

    def test_handle_start_command_starts_when_enabled
      @session.stubs(:gems_present?).returns(true)

      with_config(:'continuous_profiler.enabled' => true) do
        @session.expects(:start)
        @session.handle_start_command(create_agent_command)
      end
    end

    def test_handle_stop_command_stops_the_session
      @session.start

      @session.expects(:stop)
      @session.handle_stop_command(create_agent_command)
    end
  end
end
