# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

require 'new_relic/agent/threading/backtrace_service'
require 'new_relic/agent/threading/threaded_test_case'

if NewRelic::Agent::Threading::BacktraceService.is_supported?

  module NewRelic::Agent::Threading
    class BacktraceServiceTest < Minitest::Test
      include ThreadedTestCase

      def setup
        freeze_time
        NewRelic::Agent.instance.stats_engine.clear_stats
        @event_listener = NewRelic::Agent::EventListener.new
        @service = BacktraceService.new(@event_listener)
        setup_fake_threads
      end

      def teardown
        NewRelic::Agent.instance.stats_engine.clear_stats
        @service.stop
        teardown_fake_threads
      end

      def test_starts_when_the_first_subscription_is_added
        fake_worker_loop(@service)

        @service.subscribe(BacktraceService::ALL_TRANSACTIONS)
        assert @service.running?
      end

      def test_doesnt_start_on_resque
        with_config(:dispatcher => :resque) do
          fake_worker_loop(@service)

          @service.subscribe(BacktraceService::ALL_TRANSACTIONS)
          refute @service.running?
        end
      end

      def test_stops_when_subscription_is_removed
        fake_worker_loop(@service)

        @service.subscribe(BacktraceService::ALL_TRANSACTIONS)
        assert @service.running?

        @service.unsubscribe(BacktraceService::ALL_TRANSACTIONS)
        assert !@service.running?
      end

      def test_stops_only_once_all_subscriptions_are_removed
        fake_worker_loop(@service)

        @service.subscribe('foo')
        @service.subscribe('bar')
        assert @service.running?

        @service.unsubscribe('bar')
        assert @service.running?

        @service.unsubscribe('foo')
        assert !@service.running?
      end

      def test_stop_clears_buffered_backtraces
        fake_worker_loop(@service)

        fake_thread(:request)

        @service.subscribe('foo')
        @service.poll
        @service.unsubscribe('foo')

        assert_equal 0, @service.buffer.size
      end

      def test_harvest_returns_thread_profiles
        fake_worker_loop(@service)

        profile = @service.subscribe('foo')
        harvested_profile = @service.harvest('foo')
        assert_same(profile, harvested_profile)
      end

      def test_harvest_resets_thread_profiles
        fake_worker_loop(@service)

        @service.subscribe('foo')
        profile1 = @service.harvest('foo')
        profile2 = @service.harvest('foo')

        assert(profile1)
        assert(profile2)
        refute_same(profile1, profile2)
      end

      def test_harvest_passes_on_original_args_to_new_thread_profiles
        fake_worker_loop(@service)

        args = { 'profile_id' => 42, 'duration' => 99, 'sample_period' => 0.1 }
        @service.subscribe('foo', args)
        @service.harvest('foo')
        profile = @service.harvest('foo')

        assert_equal(args, profile.command_arguments)
      end

      def test_harvest_sets_finished_at_on_returned_thread_profile
        fake_worker_loop(@service)

        t0 = Time.now
        @service.subscribe('foo')
        harvested_profile = @service.harvest('foo')

        assert_equal t0, harvested_profile.finished_at
      end

      def test_harvest_returns_nil_if_never_subscribed
        fake_worker_loop(@service)

        profile = @service.harvest('diggle')
        assert_nil(profile)
      end

      def test_poll_forwards_backtraces_to_subscribed_profiles
        fake_worker_loop(@service)

        bt0, bt1 = ["bt0"], ["bt1"]

        thread0 = fake_thread(:request, bt0)
        thread1 = fake_thread(:differenter_request, bt1)

        profile = @service.subscribe(BacktraceService::ALL_TRANSACTIONS)
        profile.expects(:aggregate).with(bt0, :request, thread0)
        profile.expects(:aggregate).with(bt1, :differenter_request, thread1)

        @service.poll
      end

      def test_poll_does_not_forward_ignored_backtraces_to_profiles
        fake_worker_loop(@service)

        fake_thread(:ignore)

        profile = @service.subscribe(BacktraceService::ALL_TRANSACTIONS)
        profile.expects(:aggregate).never

        @service.poll
      end

      def test_poll_scrubs_backtraces_before_forwarding_to_profiles
        fake_worker_loop(@service)
        scrubbed_backtrace = []

        thread = fake_thread(:agent, ["trace"])

        AgentThread.stubs(:scrub_backtrace).
                    with(thread, any_parameters).
                    returns(scrubbed_backtrace)

        profile = @service.subscribe(BacktraceService::ALL_TRANSACTIONS)
        profile.expects(:aggregate).with(scrubbed_backtrace, :agent, thread)

        @service.poll
      end

      def test_poll_records_supportability_metrics
        fake_worker_loop(@service)

        fake_thread(:request)

        profile = @service.subscribe(BacktraceService::ALL_TRANSACTIONS)
        profile.stubs(:aggregate)

        @service.poll
        @service.poll

        # First poll doesn't record skew since we don't have a last poll time
        assert_metrics_recorded({
          'Supportability/ThreadProfiler/PollingTime' => { :call_count => 2 },
          'Supportability/ThreadProfiler/Skew'        => { :call_count => 1 }
        })
      end

      def test_subscribe_adjusts_worker_loop_period
        fake_worker_loop(@service)

        @service.subscribe('foo', 'sample_period' => 10)
        assert_has_period(10)

        @service.subscribe('bar', 'sample_period' => 5)
        assert_has_period(5)
      end

      def test_unsubscribe_adjusts_worker_loop_period
        fake_worker_loop(@service)

        @service.subscribe('foo', 'sample_period' => 10)
        @service.subscribe('bar', 'sample_period' => 5)
        @service.unsubscribe('bar')

        assert_has_period(10)
      end

      def test_subscribe_sets_profile_agent_code
        fake_worker_loop(@service)

        @service.subscribe('foo', 'profile_agent_code' => true)
        assert @service.profile_agent_code
      end

      def test_subscribe_sets_profile_agent_code_for_multiple_profiles
        fake_worker_loop(@service)

        @service.subscribe('foo', 'profile_agent_code' => true)
        @service.subscribe('bar', 'profile_agent_code' => false)
        assert @service.profile_agent_code
      end

      def test_subscribe_sets_profile_agent_code_when_missing
        fake_worker_loop(@service)

        @service.subscribe('foo')
        @service.subscribe('bar')
        assert !@service.profile_agent_code
      end

      def test_unsubscribe_sets_profile_agent_code
        fake_worker_loop(@service)

        @service.subscribe('foo', 'profile_agent_code' => true)
        @service.subscribe('bar', 'profile_agent_code' => false)
        assert @service.profile_agent_code

        @service.unsubscribe('foo')
        assert !@service.profile_agent_code
      end

      def test_sample_thread_does_not_backtrace_if_no_subscriptions
        thread = fake_thread(:request)
        thread.expects(:backtrace).never
        @service.sample_thread(thread)
      end

      def test_sample_thread_does_not_backtrace_if_ignored
        thread = fake_thread(:ignore)
        thread.expects(:backtrace).never
        @service.sample_thread(thread)
      end

      def test_sample_thread_does_not_backtrace_if_no_relevant_subscriptions
        fake_worker_loop(@service)
        @service.subscribe('foo')

        thread = fake_thread(:other)
        thread.expects(:backtrace).never
        @service.sample_thread(thread)
      end

      def test_on_transaction_finished_always_clears_buffer_for_current_thread
        fake_worker_loop(@service)

        thread = fake_thread(:request)
        @service.subscribe('foo')
        @service.poll

        fake_transaction_finished('bar', 0, 1, thread)
        assert @service.buffer.empty?
      end

      def test_on_transaction_finished_aggregates_backtraces_to_subscribed_profile
        fake_worker_loop(@service)

        thread = fake_thread(:request)
        profile = @service.subscribe('foo')

        t0 = Time.now
        @service.poll

        profile.expects(:aggregate).with(thread.backtrace, :request, thread)
        fake_transaction_finished('foo', t0.to_f, 1, thread)
      end

      def test_on_transaction_finished_does_not_aggregate_backtraces_to_non_subscribed_profiles
        fake_worker_loop(@service)

        thread = fake_thread(:request)
        profile = @service.subscribe('foo')

        t0 = Time.now
        @service.poll

        profile.expects(:aggregate).never
        fake_transaction_finished('bar', t0.to_f, 1, thread)
      end

      def test_on_transaction_finished_delivers_buffered_backtraces_for_correct_thread
        fake_worker_loop(@service)

        thread0 = fake_thread(:request)
        thread1 = fake_thread(:request)

        profile = @service.subscribe('foo')

        t0 = Time.now
        @service.poll

        profile.expects(:aggregate).with(thread0.backtrace, :request, thread0).once
        profile.expects(:aggregate).with(thread1.backtrace, :request, thread1).once

        fake_transaction_finished('foo', t0.to_f, 1, thread0)
        fake_transaction_finished('foo', t0.to_f, 1, thread1)
      end

      def test_on_transaction_finished_only_delivers_backtraces_within_transaction_time_window
        fake_worker_loop(@service)

        thread = fake_thread(:request)

        profile = @service.subscribe('foo')

        t0 = Time.now
        5.times do
          @service.poll
          advance_time(1.0)
        end

        profile.expects(:aggregate).with(thread.backtrace, :request, thread).times(2)
        fake_transaction_finished('foo', (t0 + 1).to_f, 2.0, thread)
      end

      def test_on_transaction_finished_delivers_background_backtraces
        fake_worker_loop(@service)

        thread0 = fake_thread(:background)

        profile = @service.subscribe('foo')

        t0 = Time.now
        @service.poll

        profile.expects(:aggregate).with(thread0.backtrace, :background, thread0).once

        fake_transaction_finished('foo', t0.to_f, 1, thread0, :background)
      end

      def test_does_not_deliver_non_request_backtraces_to_subscribed_profiles
        fake_worker_loop(@service)

        thread = fake_thread(:other)

        profile = @service.subscribe('foo')

        t0 = Time.now
        @service.poll

        profile.expects(:aggregate).never
        fake_transaction_finished('foo', t0.to_f, 1, thread)
      end

      def test_subscribe_sets_up_transaction_finished_subscription
        fake_worker_loop(@service)

        mark_bucket_for_thread(Thread.current, :request)
        FakeThread.list << Thread.current

        profile = @service.subscribe('foo')

        t0 = Time.now
        @service.poll

        profile.expects(:aggregate).once
        fake_transaction_finished('foo', t0.to_f, 1.0, Thread.current)
      end

      def test_service_increments_profile_poll_counts
        fake_worker_loop(@service)

        profile = @service.subscribe(BacktraceService::ALL_TRANSACTIONS)
        5.times { @service.poll }
        assert_equal(5, profile.poll_count)

        @service.unsubscribe(BacktraceService::ALL_TRANSACTIONS)
        5.times { @service.poll }
        assert_equal(5, profile.poll_count)
      end

      def test_poll_scrubs_dead_threads_from_buffer
        fake_worker_loop(@service)
        thread0 = fake_thread(:request)
        thread1 = fake_thread(:request)

        @service.subscribe('foo')
        @service.poll

        thread1.stubs(:alive?).returns(false)
        @service.poll

        assert_equal(2, @service.buffer[thread0].size)
        assert_nil(@service.buffer[thread1])

        @service.unsubscribe('foo')
      end

      def test_poll_records_polling_time
        fake_worker_loop(@service)

        profile = @service.subscribe('foo')
        def profile.increment_poll_count
          advance_time(5.0)
        end

        @service.poll

        expected = { :call_count => 1, :total_call_time => 5 }
        assert_metrics_recorded(
          { 'Supportability/ThreadProfiler/PollingTime' => expected }
        )
      end

      def test_buffer_backtrace_for_thread_should_limit_buffer_size
        fake_worker_loop(@service)

        @service.subscribe('foo')

        thread = stub
        BacktraceService::MAX_BUFFER_LENGTH.times do
          @service.buffer_backtrace_for_thread(thread, Time.now.to_f, stub, :request)
        end
        assert_equal BacktraceService::MAX_BUFFER_LENGTH, @service.buffer[thread].length

        @service.buffer_backtrace_for_thread(thread, Time.now.to_f, stub, :request)
        assert_equal BacktraceService::MAX_BUFFER_LENGTH, @service.buffer[thread].length
        assert_metrics_recorded(["Supportability/XraySessions/DroppedBacktraces"])
      end

      def test_dynamically_adjusts_worker_loop_period
        fake_worker_loop(@service)

        poll_for(0.01)
        assert_has_period 0.2
      end

      def test_doesnt_adjust_worker_loop_period_if_not_enough_overhead
        fake_worker_loop(@service)

        poll_for(0.001)
        assert_has_default_period
      end

      def test_dynamic_adjustment_returns_if_later_polls_are_shorter
        fake_worker_loop(@service)

        poll_for(0.01)
        assert_has_period 0.2

        poll_for(0.001)
        assert_has_default_period
      end

      def test_dynamic_adjustment_drives_from_config
        freeze_time
        fake_worker_loop(@service)

        with_config(:'xray_session.max_profile_overhead' => 0.1) do
          poll_for(0.01)
          assert_has_default_period
        end
      end

      def poll_for(poll_length)
        fake_last_poll_took(poll_length)
        @service.poll
      end

      def assert_has_period(value)
        assert_in_delta(value, @service.worker_loop.period, 0.001)
      end

      def assert_has_default_period
        assert_in_delta(0.1, @service.worker_loop.period, 0.001)
      end

      def fake_last_poll_took(last_poll_length)
        # We need to adjust Time.now during the midst of poll
        # Slip in before the adjust_polling_time call to advance the clock
        @service.define_singleton_method(:adjust_polling_time) do |end_time, *args|
          end_time += last_poll_length
          super(end_time, *args)
        end
      end

      def fake_transaction_finished(name, start_timestamp, duration, thread, bucket=:request)
        payload = {
          :name            => name,
          :bucket          => bucket,
          :start_timestamp => start_timestamp,
          :duration        => duration
        }
        payload[:thread] = thread if thread
        @event_listener.notify(:transaction_finished, payload)
      end

      def fake_worker_loop(service)
        dummy_loop = NewRelic::Agent::WorkerLoop.new
        dummy_loop.stubs(:run).returns(nil)
        dummy_loop.stubs(:stop).returns(nil)
        service.stubs(:worker_loop).returns(dummy_loop)
        service.effective_polling_period = 0.1
        dummy_loop
      end

      def fake_thread(bucket, backtrace=[])
        thread = FakeThread.new(:backtrace => backtrace)
        mark_bucket_for_thread(thread, bucket)

        FakeThread.list << thread
        thread
      end

      def mark_bucket_for_thread(thread, bucket)
        AgentThread.stubs(:bucket_thread).with(thread, any_parameters).returns(bucket)
      end
    end

    # These tests do not use ThreadedTestCase as FakeThread is synchronous and
    # prevents the detection of concurrency issues.
    class BacktraceServiceConcurrencyTest < Minitest::Test
      def setup
        NewRelic::Agent.instance.stats_engine.clear_stats
        @service = BacktraceService.new
      end

      def teardown
        @service.stop
      end

      def test_adding_subscriptions_is_thread_safe
        @service.worker_loop.propagate_errors = true

        @service.subscribe('foo', { 'sample_period' => 0.01 })

        wait_for_backtrace_service_poll(:service => @service)

        10000.times do
          @service.subscribe(BacktraceService::ALL_TRANSACTIONS)
          @service.unsubscribe(BacktraceService::ALL_TRANSACTIONS)
        end

        @service.unsubscribe('foo')

        @service.worker_thread.join
      end
    end

  end
else
  module NewRelic::Agent::Threading
    class BacktraceServiceUnsupportedTest < Minitest::Test
      def test_is_not_supported?
        assert_false BacktraceService.is_supported?
      end

      def test_safely_ignores_subscribe
        service = BacktraceService.new
        service.subscribe('fine/ignore/me')

        assert_false service.subscribed?('fine/ignore/me')
      end

      def test_safely_ignores_unsubscribe
        service = BacktraceService.new

        service.subscribe('fine/ignore/me')
        service.unsubscribe('fine/ignore/me')

        assert_false service.subscribed?('fine/ignore/me')
      end

      def test_cannot_start
        service = BacktraceService.new

        service.start

        assert_false service.running?
      end

    end
  end
end
