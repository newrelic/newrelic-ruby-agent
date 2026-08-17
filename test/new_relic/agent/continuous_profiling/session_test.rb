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
      with_config(:'profiling.enabled' => false) do
        @session.expects(:start).never
        @session.maybe_start
      end
    end

    def test_maybe_start_does_nothing_on_jruby
      with_config(:'profiling.enabled' => true) do
        NewRelic::LanguageSupport.stub :jruby?, true do
          @session.expects(:start).never
          @session.maybe_start
        end
      end
    end

    def test_maybe_start_starts_when_enabled_and_supported
      @session.stubs(:gems_present?).returns(true)

      with_config(:'profiling.enabled' => true) do
        NewRelic::LanguageSupport.stub :jruby?, false do
          @session.expects(:start)
          @session.maybe_start
        end
      end
    end

    def test_maybe_start_does_nothing_when_gems_missing
      @session.stubs(:gems_present?).returns(false)

      with_config(:'profiling.enabled' => true) do
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
      report = {:samples => 3, :mode => :cpu}
      sampler = NewRelic::Agent::ContinuousProfiling::StackProfSampler.new
      sampler.expects(:stop_and_collect).returns(report)
      sampler.expects(:start)
      @session.instance_variable_set(:@sampler, sampler)
      @session.instance_variable_set(:@running, true)
      @session.instance_variable_set(:@sampler_active, true)
      @session.expects(:encode_and_export).with(report)

      @session.send(:harvest_and_send)

      assert @session.instance_variable_get(:@sampler_active)
      assert_metrics_recorded('Supportability/Ruby/Profiling/Sampling/Duration')
    end

    def test_harvest_and_send_restarts_the_sampler_before_encoding_and_exporting
      report = {:samples => 3, :mode => :cpu}
      sequence = Mocha::Sequence.new('harvest')
      sampler = NewRelic::Agent::ContinuousProfiling::StackProfSampler.new
      sampler.expects(:stop_and_collect).returns(report).in_sequence(sequence)
      sampler.expects(:start).in_sequence(sequence)
      @session.instance_variable_set(:@sampler, sampler)
      @session.instance_variable_set(:@running, true)
      @session.instance_variable_set(:@sampler_active, true)
      @session.expects(:encode_and_export).with(report).in_sequence(sequence)

      @session.send(:harvest_and_send)
    end

    def test_harvest_and_send_restarts_the_sampler_even_when_collection_raises
      sampler = NewRelic::Agent::ContinuousProfiling::StackProfSampler.new
      sampler.expects(:stop_and_collect).raises('boom')
      sampler.expects(:start)
      @session.instance_variable_set(:@sampler, sampler)
      @session.instance_variable_set(:@running, true)
      @session.instance_variable_set(:@sampler_active, true)

      @session.send(:harvest_and_send)
    end

    def test_harvest_and_send_restarts_the_sampler_even_when_encode_and_export_raises
      report = {:samples => 3, :mode => :cpu}
      sampler = NewRelic::Agent::ContinuousProfiling::StackProfSampler.new
      sampler.expects(:stop_and_collect).returns(report)
      sampler.expects(:start)
      @session.instance_variable_set(:@sampler, sampler)
      @session.instance_variable_set(:@running, true)
      @session.instance_variable_set(:@sampler_active, true)
      @session.stubs(:encode_and_export).raises('boom')

      @session.send(:harvest_and_send)
    end

    def test_harvest_and_send_is_a_no_op_when_the_sampler_is_not_active
      sampler = NewRelic::Agent::ContinuousProfiling::StackProfSampler.new
      sampler.expects(:stop_and_collect).never
      @session.instance_variable_set(:@sampler, sampler)
      @session.instance_variable_set(:@sampler_active, false)

      @session.send(:harvest_and_send)
    end

    def test_wait_for_next_tick_or_stop_returns_false_immediately_when_already_stopped
      @session.instance_variable_set(:@running, false)

      refute @session.send(:wait_for_next_tick_or_stop)
    end

    def test_run_loop_performs_exactly_one_final_harvest_when_already_stopped
      # Simulates stop() having already flipped @running to false before the loop's
      # first check -- e.g. the loop was sleeping when stop() was called. Exactly one
      # harvest of whatever was pending should still happen (see #harvest_and_send).
      report = {:samples => 2, :mode => :cpu}
      sampler = NewRelic::Agent::ContinuousProfiling::StackProfSampler.new
      sampler.expects(:stop_and_collect).once.returns(report)
      @session.instance_variable_set(:@sampler, sampler)
      @session.instance_variable_set(:@sampler_active, true)
      @session.instance_variable_set(:@running, false)
      @session.expects(:encode_and_export).once

      @session.send(:run_loop)
    end

    def test_run_loop_does_not_double_harvest_when_already_flushed
      # Simulates stop() being called just after a harvest already ran and drained the
      # sampler (@sampler_active already false) -- run_loop's final pass must not attempt
      # a second collection.
      sampler = NewRelic::Agent::ContinuousProfiling::StackProfSampler.new
      sampler.expects(:stop_and_collect).never
      @session.instance_variable_set(:@sampler, sampler)
      @session.instance_variable_set(:@sampler_active, false)
      @session.instance_variable_set(:@running, false)

      @session.send(:run_loop)
    end

    # The rest of encode_and_export needs google-protobuf, not loadable here -- this skip
    # happens before that require, so it's the one part testable without the real gem.
    def test_encode_and_export_skips_when_not_connected
      NewRelic::Agent.agent.stubs(:connected?).returns(false)
      NewRelic::Agent.agent.service.expects(:profiles_data).never

      @session.send(:encode_and_export, {:samples => 0, :mode => :cpu})

      assert_metrics_recorded('Supportability/Ruby/Profiling/Export/SkippedNotConnected')
    end

    def test_server_source_configuration_added_starts_session_when_newly_enabled
      @session.stubs(:gems_present?).returns(true)

      with_config(:'profiling.enabled' => true) do
        NewRelic::LanguageSupport.stub :jruby?, false do
          @session.expects(:start)
          @events.notify(:server_source_configuration_added)
        end
      end
    end

    def test_server_source_configuration_added_does_not_start_when_gems_missing
      @session.stubs(:gems_present?).returns(false)

      with_config(:'profiling.enabled' => true) do
        NewRelic::LanguageSupport.stub :jruby?, false do
          @session.expects(:start).never
          @events.notify(:server_source_configuration_added)
        end
      end
    end

    def test_server_source_configuration_added_stops_session_when_newly_disabled
      @session.start

      with_config(:'profiling.enabled' => false) do
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

    def test_start_subscribes_the_transaction_hooks
      refute @events.instance_variable_get(:@events).key?(:start_transaction)

      @session.start

      refute_empty @events.instance_variable_get(:@events)[:start_transaction]
      refute_empty @events.instance_variable_get(:@events)[:transaction_finished]
    end

    def test_stop_unsubscribes_the_transaction_hooks
      @session.start

      @session.stop

      assert_empty @events.instance_variable_get(:@events)[:start_transaction]
      assert_empty @events.instance_variable_get(:@events)[:transaction_finished]
    end

    def test_fork_restart_does_not_double_subscribe_the_transaction_hooks
      @session.start

      real_pid = Process.pid
      Process.stubs(:pid).returns(real_pid + 1)
      NewRelic::Agent::Threading::AgentThread.stubs(:create).returns(stub_everything('post-fork thread'))
      @events.notify(:start_transaction)

      assert_equal 1, @events.instance_variable_get(:@events)[:start_transaction].size
    end

    def stub_segment(guid:, start_time:, duration:, finished: true)
      stub(:guid => guid, :start_time => start_time, :end_time => start_time + duration, :duration => duration, :finished? => finished)
    end

    def test_transaction_finished_stops_recording_once_the_segment_ranges_limit_is_reached
      @session.start
      full_ranges = Array.new(Session::MAX_SEGMENT_RANGES) { ['t', 's', 0.0, 1.0] }
      @session.instance_variable_set(:@segment_ranges, full_ranges)
      root = stub_segment(guid: 'span123', start_time: 10.0, duration: 2.5)
      txn = stub(:trace_id_if_generated => 'trace123', :initial_segment => root, :segments => [root])
      NewRelic::Agent::Tracer.stubs(:current_transaction).returns(txn)

      @events.notify(:transaction_finished)

      assert_equal Session::MAX_SEGMENT_RANGES, @session.instance_variable_get(:@segment_ranges).size
      assert_metrics_recorded('Supportability/Ruby/Profiling/SegmentRanges/LimitExceeded')
    end

    def test_transaction_finished_records_a_range_for_the_root_segment_while_running
      @session.start
      root = stub_segment(guid: 'span123', start_time: 10.0, duration: 2.5)
      txn = stub(:trace_id_if_generated => 'trace123', :initial_segment => root, :segments => [root])
      NewRelic::Agent::Tracer.stubs(:current_transaction).returns(txn)

      @events.notify(:transaction_finished)

      assert_equal [['trace123', 'span123', 10.0, 12.5]], @session.instance_variable_get(:@segment_ranges)
    end

    def test_transaction_finished_records_ranges_for_qualifying_child_segments_too
      @session.start
      root = stub_segment(guid: 'root_span', start_time: 10.0, duration: 2.5)
      child = stub_segment(guid: 'child_span', start_time: 10.5, duration: 0.5)
      txn = stub(:trace_id_if_generated => 'trace123', :initial_segment => root, :segments => [root, child])
      NewRelic::Agent::Tracer.stubs(:current_transaction).returns(txn)

      with_config(:'profiling.sample_period' => 0.01) do
        @events.notify(:transaction_finished)
      end

      assert_equal(
        [['trace123', 'root_span', 10.0, 12.5], ['trace123', 'child_span', 10.5, 11.0]],
        @session.instance_variable_get(:@segment_ranges)
      )
    end

    def test_transaction_finished_excludes_child_segments_shorter_than_one_sample_period
      @session.start
      root = stub_segment(guid: 'root_span', start_time: 10.0, duration: 2.5)
      tiny_child = stub_segment(guid: 'tiny_child_span', start_time: 10.5, duration: 0.001)
      txn = stub(:trace_id_if_generated => 'trace123', :initial_segment => root, :segments => [root, tiny_child])
      NewRelic::Agent::Tracer.stubs(:current_transaction).returns(txn)

      with_config(:'profiling.sample_period' => 0.01) do
        @events.notify(:transaction_finished)
      end

      assert_equal [['trace123', 'root_span', 10.0, 12.5]], @session.instance_variable_get(:@segment_ranges)
    end

    def test_transaction_finished_excludes_unfinished_segments
      @session.start
      root = stub_segment(guid: 'root_span', start_time: 10.0, duration: 2.5)
      unfinished_child = stub_segment(guid: 'unfinished_span', start_time: 10.5, duration: 1.0, finished: false)
      txn = stub(:trace_id_if_generated => 'trace123', :initial_segment => root, :segments => [root, unfinished_child])
      NewRelic::Agent::Tracer.stubs(:current_transaction).returns(txn)

      @events.notify(:transaction_finished)

      assert_equal [['trace123', 'root_span', 10.0, 12.5]], @session.instance_variable_get(:@segment_ranges)
    end

    def test_transaction_finished_does_not_record_a_range_when_not_running
      NewRelic::Agent::Tracer.expects(:current_transaction).never

      @events.notify(:transaction_finished)

      assert_empty @session.instance_variable_get(:@segment_ranges)
    end

    def test_transaction_finished_does_not_record_a_range_without_a_current_transaction
      @session.start
      NewRelic::Agent::Tracer.stubs(:current_transaction).returns(nil)

      @events.notify(:transaction_finished)

      assert_empty @session.instance_variable_get(:@segment_ranges)
    end

    def test_harvest_and_send_drains_segment_ranges_into_the_report
      report = {:samples => 3, :mode => :cpu}
      sampler = NewRelic::Agent::ContinuousProfiling::StackProfSampler.new
      sampler.expects(:stop_and_collect).returns(report)
      sampler.expects(:start)
      @session.instance_variable_set(:@sampler, sampler)
      @session.instance_variable_set(:@running, true)
      @session.instance_variable_set(:@sampler_active, true)
      @session.instance_variable_set(:@segment_ranges, [['abc123', 'def456', 1.0, 2.0]])
      @session.expects(:encode_and_export).with(
        report.merge(segment_ranges: [['abc123', 'def456', 1.0, 2.0]])
      )

      @session.send(:harvest_and_send)

      assert_empty @session.instance_variable_get(:@segment_ranges)
    end

    def test_before_shutdown_stops_the_session
      @session.start

      @session.expects(:stop)
      @events.notify(:before_shutdown)
    end

    def test_handle_start_command_raises_when_gems_missing
      @session.stubs(:gems_present?).returns(false)

      with_config(:'profiling.enabled' => true) do
        assert_raises NewRelic::Agent::Commands::AgentCommandRouter::AgentCommandError do
          @session.handle_start_command(create_agent_command)
        end
      end

      refute_predicate @session, :running?
    end

    def test_handle_start_command_works_even_when_disabled_via_config
      @session.stubs(:gems_present?).returns(true)

      with_config(:'profiling.enabled' => false) do
        @session.handle_start_command(create_agent_command)
      end

      assert_predicate @session, :running?
    end

    def test_handle_start_command_raises_under_high_security_even_with_gems_present
      @session.stubs(:gems_present?).returns(true)

      with_config(:high_security => true) do
        assert_raises NewRelic::Agent::Commands::AgentCommandRouter::AgentCommandError do
          @session.handle_start_command(create_agent_command)
        end
      end

      refute_predicate @session, :running?
    end

    def test_handle_start_command_raises_on_jruby_even_with_gems_present
      @session.stubs(:gems_present?).returns(true)

      NewRelic::LanguageSupport.stub :jruby?, true do
        assert_raises NewRelic::Agent::Commands::AgentCommandRouter::AgentCommandError do
          @session.handle_start_command(create_agent_command)
        end
      end

      refute_predicate @session, :running?
    end

    def test_handle_start_command_raises_when_already_running
      @session.stubs(:gems_present?).returns(true)

      with_config(:'profiling.enabled' => true) do
        @session.start

        assert_raises NewRelic::Agent::Commands::AgentCommandRouter::AgentCommandError do
          @session.handle_start_command(create_agent_command)
        end
      end
    end

    def test_handle_start_command_starts_when_enabled
      @session.stubs(:gems_present?).returns(true)

      with_config(:'profiling.enabled' => true) do
        @session.expects(:start)
        @session.handle_start_command(create_agent_command)
      end
    end

    def test_handle_stop_command_stops_the_session
      @session.start

      @session.expects(:stop)
      @session.handle_stop_command(create_agent_command)
    end

    def test_handle_start_command_logs_a_warning_naming_the_missing_gem
      @session.stubs(:stackprof_present?).returns(false)
      @session.stubs(:protobuf_present?).returns(true)

      with_config(:'profiling.enabled' => true) do
        NewRelic::Agent.logger.expects(:warn).with('Continuous profiling is not available: the stackprof gem is not installed.')

        assert_raises NewRelic::Agent::Commands::AgentCommandRouter::AgentCommandError do
          @session.handle_start_command(create_agent_command)
        end
      end
    end

    def test_handle_start_command_logs_a_warning_naming_every_unmet_condition
      @session.stubs(:stackprof_present?).returns(false)
      @session.stubs(:protobuf_present?).returns(false)

      with_config(:high_security => true) do
        NewRelic::LanguageSupport.stub :jruby?, true do
          NewRelic::Agent.logger.expects(:warn).with(
            'Continuous profiling is not available: the stackprof gem is not installed, ' \
            'the google-protobuf gem is not installed, JRuby is not supported, high security mode is enabled.'
          )

          assert_raises NewRelic::Agent::Commands::AgentCommandRouter::AgentCommandError do
            @session.handle_start_command(create_agent_command)
          end
        end
      end
    end

    def test_evaluate_and_apply_logs_a_warning_when_enabled_via_config_but_unsupported
      @session.stubs(:gems_present?).returns(false)
      @session.stubs(:stackprof_present?).returns(false)
      @session.stubs(:protobuf_present?).returns(true)

      with_config(:'profiling.enabled' => true) do
        NewRelic::Agent.logger.expects(:warn).with('Continuous profiling is not available: the stackprof gem is not installed.')
        @session.expects(:start).never

        @events.notify(:server_source_configuration_added)
      end
    end

    def test_evaluate_and_apply_does_not_log_a_warning_when_disabled_via_config
      @session.stubs(:gems_present?).returns(false)

      with_config(:'profiling.enabled' => false) do
        NewRelic::Agent.logger.expects(:warn).never

        @events.notify(:server_source_configuration_added)
      end
    end

    def test_evaluate_and_apply_does_not_log_a_warning_when_supported
      @session.stubs(:gems_present?).returns(true)

      with_config(:'profiling.enabled' => true) do
        NewRelic::LanguageSupport.stub :jruby?, false do
          NewRelic::Agent.logger.expects(:warn).never
          @session.stubs(:start)

          @events.notify(:server_source_configuration_added)
        end
      end
    end
  end
end
