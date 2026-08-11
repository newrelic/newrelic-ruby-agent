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
      report = {:samples => 3, :mode => :cpu}
      sampler = NewRelic::Agent::ContinuousProfiling::StackProfSampler.new
      sampler.expects(:stop_and_collect).returns(report)
      sampler.expects(:start)
      @session.instance_variable_set(:@sampler, sampler)
      @session.instance_variable_set(:@running, true)
      @session.stubs(:encode_and_export).raises('boom')

      @session.send(:harvest_and_send)
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

    def test_start_transaction_records_the_active_trace_id_while_running
      @session.instance_variable_set(:@running, true)

      in_transaction('txn') do |txn|
        @events.notify(:start_transaction)

        assert_includes @session.instance_variable_get(:@active_trace_ids), txn.trace_id
      end
    end

    def test_start_transaction_does_not_record_a_trace_id_when_not_running
      in_transaction('txn') do
        @events.notify(:start_transaction)

        assert_empty @session.instance_variable_get(:@active_trace_ids)
      end
    end

    def test_start_transaction_stops_recording_once_the_active_trace_ids_limit_is_reached
      @session.instance_variable_set(:@running, true)
      full_set = Set.new(1..Session::MAX_ACTIVE_TRACE_IDS)
      @session.instance_variable_set(:@active_trace_ids, full_set)

      # Capacity check short-circuits before Tracer.current_trace_id is called, so no
      # transaction needs to be in flight here.
      @events.notify(:start_transaction)

      assert_equal Session::MAX_ACTIVE_TRACE_IDS, @session.instance_variable_get(:@active_trace_ids).size
      assert_metrics_recorded('Supportability/Ruby/Profiling/ActiveTraceIds/LimitExceeded')
    end

    def stub_segment(guid:, start_time:, duration:, finished: true)
      stub(:guid => guid, :start_time => start_time, :end_time => start_time + duration, :duration => duration, :finished? => finished)
    end

    def test_transaction_finished_stops_recording_once_the_segment_ranges_limit_is_reached
      @session.instance_variable_set(:@running, true)
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
      @session.instance_variable_set(:@running, true)
      root = stub_segment(guid: 'span123', start_time: 10.0, duration: 2.5)
      txn = stub(:trace_id_if_generated => 'trace123', :initial_segment => root, :segments => [root])
      NewRelic::Agent::Tracer.stubs(:current_transaction).returns(txn)

      @events.notify(:transaction_finished)

      assert_equal [['trace123', 'span123', 10.0, 12.5]], @session.instance_variable_get(:@segment_ranges)
    end

    def test_transaction_finished_records_ranges_for_qualifying_child_segments_too
      @session.instance_variable_set(:@running, true)
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
      @session.instance_variable_set(:@running, true)
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
      @session.instance_variable_set(:@running, true)
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
      @session.instance_variable_set(:@running, true)
      NewRelic::Agent::Tracer.stubs(:current_transaction).returns(nil)

      @events.notify(:transaction_finished)

      assert_empty @session.instance_variable_get(:@segment_ranges)
    end

    def test_harvest_and_send_drains_active_trace_ids_and_segment_ranges_into_the_report
      report = {:samples => 3, :mode => :cpu}
      sampler = NewRelic::Agent::ContinuousProfiling::StackProfSampler.new
      sampler.expects(:stop_and_collect).returns(report)
      sampler.expects(:start)
      @session.instance_variable_set(:@sampler, sampler)
      @session.instance_variable_set(:@running, true)
      @session.instance_variable_set(:@active_trace_ids, Set.new(['abc123']))
      @session.instance_variable_set(:@segment_ranges, [['abc123', 'def456', 1.0, 2.0]])
      @session.expects(:encode_and_export).with(
        report.merge(active_trace_ids: ['abc123'], segment_ranges: [['abc123', 'def456', 1.0, 2.0]])
      )

      @session.send(:harvest_and_send)

      assert_empty @session.instance_variable_get(:@active_trace_ids)
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

    def test_handle_start_command_raises_when_disabled_via_config
      @session.stubs(:gems_present?).returns(true)

      with_config(:'profiling.enabled' => false) do
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
  end
end
