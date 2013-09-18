# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

require 'new_relic/agent/threading/thread_profiling_service'
require 'new_relic/agent/threading/threaded_test_case'

if NewRelic::Agent::Commands::ThreadProfilerSession.is_supported?

  module NewRelic::Agent::Threading
    module ThreadProfilingServiceTestHelpers
      def fake_worker_loop(service)
        dummy_loop = NewRelic::Agent::WorkerLoop.new
        dummy_loop.stubs(:run).returns(nil)
        dummy_loop.stubs(:stop).returns(nil)
        service.stubs(:worker_loop).returns(dummy_loop)
        dummy_loop
      end
    end

    class ThreadProfilingServiceTest < Test::Unit::TestCase
      include ThreadedTestCase
      include ThreadProfilingServiceTestHelpers

      def setup
        NewRelic::Agent.instance.stats_engine.clear_stats
        @service = ThreadProfilingService.new
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

      def test_each_backtrace_with_bucket
        faketrace, alsofaketrace = mock, mock

        FakeThread.list << FakeThread.new(
          :bucket => :request,
          :backtrace => faketrace)
        FakeThread.list << FakeThread.new(
          :bucket => :differenter_request,
          :backtrace => alsofaketrace)

        backtrabuckets = []
        @service.each_backtrace_with_bucket do |backtrace, bucket|
          backtrabuckets << [backtrace, bucket]
        end

        expected = [[faketrace, :request], [alsofaketrace, :differenter_request]]
        assert_equal expected, backtrabuckets
      end

    end

    # These tests do not use ThreadedTestCase as FakeThread is synchronous and
    # prevents the detection of concurrency issues.
    class ThreadProfilingServiceConcurrencyTest < Test::Unit::TestCase
      include ThreadProfilingServiceTestHelpers

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
