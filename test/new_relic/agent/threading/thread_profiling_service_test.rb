# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

require 'new_relic/agent/threading/thread_profiling_service'
require 'new_relic/agent/threading/threaded_test_case'

if NewRelic::Agent::Commands::ThreadProfilerSession.is_supported?

  module NewRelic::Agent::Threading
    class ThreadProfilingServiceTest < Test::Unit::TestCase
      include ThreadedTestCase

      def setup
        NewRelic::Agent.instance.stats_engine.clear_stats
        @event_listener = NewRelic::Agent::EventListener.new
        @service = ThreadProfilingService.new(@event_listener)
        setup_fake_threads
      end

      def teardown
        NewRelic::Agent.instance.stats_engine.clear_stats
        @service.stop
        teardown_fake_threads
      end

      def test_starts_when_the_first_subscription_is_added
        fake_worker_loop(@service)

        @service.subscribe(ThreadProfilingService::ALL_TRANSACTIONS)
        assert @service.running?
      end

      def test_stops_when_subscription_is_removed
        fake_worker_loop(@service)

        @service.subscribe(ThreadProfilingService::ALL_TRANSACTIONS)
        assert @service.running?

        @service.unsubscribe(ThreadProfilingService::ALL_TRANSACTIONS)
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
        assert_not_same(profile1, profile2)
      end

      def test_harvest_passes_on_original_args_to_new_thread_profiles
        fake_worker_loop(@service)

        args = { 'profile_id' => 42, 'duration' => 99, 'sample_period' => 0.1 }
        @service.subscribe('foo', args)
        @service.harvest('foo')
        profile = @service.harvest('foo')

        assert_equal(args, profile.command_arguments)
      end

      def test_harvest_returns_nil_if_never_subscribed
        fake_worker_loop(@service)

        profile = @service.harvest('diggle')
        assert_nil(profile)
      end

      def test_poll_forwards_backtraces_to_subscribed_profiles
        fake_worker_loop(@service)

        bt0, bt1 = mock('bt0'), mock('bt1')

        FakeThread.list << FakeThread.new(
          :bucket => :request,
          :backtrace => bt0)
        FakeThread.list << FakeThread.new(
          :bucket => :differenter_request,
          :backtrace => bt1)

        profile = @service.subscribe(ThreadProfilingService::ALL_TRANSACTIONS)
        profile.expects(:aggregate).with(bt0, :request)
        profile.expects(:aggregate).with(bt1, :differenter_request)

        @service.poll
      end

      def test_poll_does_not_forward_ignored_backtraces_to_profiles
        fake_worker_loop(@service)

        faketrace = mock('faketrace')
        FakeThread.list << FakeThread.new(
          :bucket => :ignore,
          :backtrace => faketrace)

        profile = @service.subscribe(ThreadProfilingService::ALL_TRANSACTIONS)
        profile.expects(:aggregate).never

        @service.poll
      end

      def test_poll_scrubs_backtraces_before_forwarding_to_profiles
        fake_worker_loop(@service)
        raw_backtarce = mock('raw')
        scrubbed_backtrace = mock('scrubbed')

        FakeThread.list << FakeThread.new(
          :bucket => :agent,
          :backtrace => raw_backtarce,
          :scrubbed_backtrace => scrubbed_backtrace)

        profile = @service.subscribe(ThreadProfilingService::ALL_TRANSACTIONS)
        profile.expects(:aggregate).with(scrubbed_backtrace, :agent)

        @service.poll
      end

      def test_subscribe_adjusts_worker_loop_period
        dummy_loop = fake_worker_loop(@service)

        @service.subscribe('foo', 'sample_period' => 10)
        assert_equal(10, dummy_loop.period)

        @service.subscribe('bar', 'sample_period' => 5)
        assert_equal(5, dummy_loop.period)
      end

      def test_unsubscribe_adjusts_worker_loop_period
        dummy_loop = fake_worker_loop(@service)

        @service.subscribe('foo', 'sample_period' => 10)
        @service.subscribe('bar', 'sample_period' => 5)
        @service.unsubscribe('bar')

        assert_equal(10, dummy_loop.period)
      end

      def test_subscribe_sets_profile_agent_code
        fake_worker_loop(@service)

        @service.subscribe('foo', 'profile_agent_code' => true)
        assert @service.profile_agent_code
      end

      def test_sample_thread_does_not_backtrace_if_no_subscriptions
        thread = fake_thread(:bucket => :request)
        thread.expects(:backtrace).never
        @service.sample_thread(thread)
      end

      def test_sample_thread_does_not_backtrace_if_ignored
        thread = fake_thread(:bucket => :ignore)
        thread.expects(:backtrace).never
        @service.sample_thread(thread)
      end

      def test_sample_thread_does_not_backtrace_if_no_relevant_subscriptions
        fake_worker_loop(@service)
        @service.subscribe('foo')

        thread = fake_thread(:bucket => :other)
        thread.expects(:backtrace).never
        @service.sample_thread(thread)
      end

      def test_on_transaction_finished_always_clears_buffer_for_current_thread
        fake_worker_loop(@service)

        thread = fake_thread(:bucket => :request)
        @service.subscribe('foo')
        @service.poll

        @service.on_transaction_finished('bar', Time.at(0), 1, {}, thread)
        assert @service.buffer.empty?
      end

      def test_on_transaction_finished_aggregates_backtraces_to_subscribed_profile
        fake_worker_loop(@service)

        thread = fake_thread(:bucket => :request)
        profile = @service.subscribe('foo')

        t0 = freeze_time
        @service.poll

        profile.expects(:aggregate).with(thread.backtrace, :request)
        @service.on_transaction_finished('foo', t0, 1, {}, thread)
      end

      def test_on_transaction_finished_does_not_aggregate_backtraces_to_non_subscribed_profiles
        fake_worker_loop(@service)

        thread = fake_thread(:bucket => :request)
        profile = @service.subscribe('foo')

        t0 = freeze_time
        @service.poll

        profile.expects(:aggregate).never
        @service.on_transaction_finished('bar', t0, 1, {}, thread)
      end

      def test_on_transaction_finished_delivers_buffered_backtraces_for_correct_thread
        fake_worker_loop(@service)

        thread0 = fake_thread(:bucket => :request)
        thread1 = fake_thread(:bucket => :request)

        profile = @service.subscribe('foo')

        t0 = freeze_time
        @service.poll

        profile.expects(:aggregate).with(thread0.backtrace, :request).once
        profile.expects(:aggregate).with(thread1.backtrace, :request).once

        @service.on_transaction_finished('foo', t0, 1, {}, thread0)
        @service.on_transaction_finished('foo', t0, 1, {}, thread1)
      end

      def test_on_transaction_finished_only_delivers_backtraces_within_transaction_time_window
        fake_worker_loop(@service)

        thread = fake_thread(:bucket => :request)

        profile = @service.subscribe('foo')

        t0 = freeze_time
        4.times do
          @service.poll
          advance_time(1.0)
        end

        profile.expects(:aggregate).with(thread.backtrace, :request).times(2)
        @service.on_transaction_finished('foo', t0 + 1, 2.0, {}, thread)
      end

      def test_does_not_deliver_non_request_backtraces_to_subscribed_profiles
        fake_worker_loop(@service)

        thread = fake_thread(:bucket => :other)

        profile = @service.subscribe('foo')

        t0 = freeze_time
        @service.poll

        profile.expects(:aggregate).never
        @service.on_transaction_finished('foo', t0, 1, {}, thread)
      end

      def test_subscribe_sets_up_transaction_finished_subscription
        fake_worker_loop(@service)

        Thread.current[:bucket] = :request
        FakeThread.list << Thread.current

        profile = @service.subscribe('foo')

        t0 = freeze_time
        @service.poll

        profile.expects(:aggregate).once
        @event_listener.notify(:transaction_finished, 'foo', t0, 1.0, {})
      ensure
        Thread.current[:bucket] = nil
      end

      def test_service_increments_profile_poll_counts
        fake_worker_loop(@service)

        profile = @service.subscribe(ThreadProfilingService::ALL_TRANSACTIONS)
        5.times { @service.poll }
        assert_equal(5, profile.poll_count)

        @service.unsubscribe(ThreadProfilingService::ALL_TRANSACTIONS)
        5.times { @service.poll }
        assert_equal(5, profile.poll_count)
      end

      def test_poll_records_polling_time
        fake_worker_loop(@service)

        freeze_time

        profile = @service.subscribe('foo')
        def profile.increment_poll_count
          advance_time(5.0)
        end

        @service.poll

        expected = { :call_count => 1, :total_call_time => 5}
        assert_metrics_recorded(
          { 'Supportability/ThreadProfiler/PollingTime' => expected }
        )
      end

      def fake_worker_loop(service)
        dummy_loop = NewRelic::Agent::WorkerLoop.new
        dummy_loop.stubs(:run).returns(nil)
        dummy_loop.stubs(:stop).returns(nil)
        service.stubs(:worker_loop).returns(dummy_loop)
        dummy_loop
      end

      def fake_thread(opts={})
        defaults = {
          :backtrace => mock('backtrace')
        }
        thread = FakeThread.new(defaults.merge(opts))
        FakeThread.list << thread
        thread
      end
    end

    # These tests do not use ThreadedTestCase as FakeThread is synchronous and
    # prevents the detection of concurrency issues.
    class ThreadProfilingServiceConcurrencyTest < Test::Unit::TestCase
      def setup
        NewRelic::Agent.instance.stats_engine.clear_stats
        @service = ThreadProfilingService.new
      end

      def teardown
        @service.stop
      end

      def test_adding_subscriptions_is_thread_safe
        @service.worker_loop.propagate_errors = true

        @service.subscribe('foo', { 'sample_period' => 0.01 })

        10000.times do
          @service.subscribe(ThreadProfilingService::ALL_TRANSACTIONS)
          @service.unsubscribe(ThreadProfilingService::ALL_TRANSACTIONS)
        end

        @service.unsubscribe('foo')

        @service.worker_thread.join
      end
    end

  end
end
