# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

require 'new_relic/agent/threading/thread_profiling_service'
require 'new_relic/agent/threading/threaded_test_case'

if NewRelic::Agent::Commands::ThreadProfiler.is_supported?

  module NewRelic::Agent::Threading
    module ThreadProfilingServiceTestHelpers
      def create_client(name, overrides={})
        defaults = {
          :finished? => false,
          :requested_period => 0,
          :aggregate => nil,
          :increment_poll_count => nil
        }

        client = stub(name, defaults.merge(overrides))
        client.stubs(:finished?).returns(false, true) unless overrides.has_key? :finished?
        client
      end

      def fake_worker_loop(service)
        dummy_loop = stub(:run => nil, :stop => nil, :period= => nil)
        service.stubs(:worker_loop).returns(dummy_loop)
        dummy_loop
      end
    end

    class ThreadProfilingServiceTest < ThreadedTestCase
      include ThreadProfilingServiceTestHelpers

      def setup
        NewRelic::Agent.instance.stats_engine.clear_stats
        @service = ThreadProfilingService.new
        super
      end

      def teardown
        @service.stop
        super
      end

      def create_client(name, overrides={})
        defaults = {
          :finished? => false,
          :requested_period => 0,
          :aggregate => nil,
          :increment_poll_count => nil
        }

        client = stub(name, defaults.merge(overrides))
        client.stubs(:finished?).returns(false, true) unless overrides[:finished?]
        client
      end

      def test_starts_when_the_first_client_is_added
        fake_worker_loop(@service)

        client = @service.add_client(create_client('client', :finished? => false))
        assert @service.running?
      end

      def test_stops_without_clients
        fake_worker_loop(@service)

        client = @service.add_client(create_client('client', :finished? => false))
        assert @service.running?

        client.stubs(:finished?).returns(true)
        @service.poll

        assert_false @service.running?
      end

      def test_poll_stops_the_worker_loop_only_when_all_clients_are_finished
        dummy_loop = fake_worker_loop(@service)

        first_client = @service.add_client(create_client('client1', :finished? => false))
        second_client = @service.add_client(create_client('client2', :finished? => false))
        assert @service.running?

        first_client.stubs(:finished?).returns(true)
        @service.poll
        assert @service.running?

        second_client.stubs(:finished?).returns(true)
        dummy_loop.expects(:stop)
        @service.poll
        assert_false @service.running?
      end

      def test_wait_sets_thread_to_nil
        @service.worker_thread = mock(:join)
        @service.wait
        assert_nil @service.worker_thread
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

      def test_poll_forwards_backtraces_to_clients
        faketrace, alsofaketrace = mock('faketrace'), mock('alsofaketrace')

        FakeThread.list << FakeThread.new(
          :bucket => :request,
          :backtrace => faketrace)
        FakeThread.list << FakeThread.new(
          :bucket => :differenter_request,
          :backtrace => alsofaketrace)

        carebear = create_client('carebear')
        carebear.expects(:aggregate).with(faketrace, :request)
        carebear.expects(:aggregate).with(alsofaketrace, :differenter_request)

        @service.add_client(carebear)
        @service.wait
      end

      def test_poll_does_not_forward_ignored_backtraces_to_clients
        faketrace = mock('faketrace')
        FakeThread.list << FakeThread.new(
          :bucket => :ignore,
          :backtrace => faketrace)

        ignorant_client = create_client('ignorant')
        ignorant_client.expects(:aggregate).never


        @service.add_client(ignorant_client)
        @service.wait
      end

      def test_poll_forwards_scrubbed_backtraces_to_clients_instead_of_raw
        raw_backtarce = mock('raw')
        scrubbed_backtrace = mock('scrubbed')

        FakeThread.list << FakeThread.new(
          :bucket => :agent,
          :backtrace => raw_backtarce,
          :scrubbed_backtrace => scrubbed_backtrace)

        $debug = true
        client = create_client('client')
        client.expects(:aggregate).with(scrubbed_backtrace, :agent)

        @service.add_client(client)
        @service.wait
      end

      def test_poll_adjusts_worker_loop_period_to_minimum_client_period
        dummy_loop = fake_worker_loop(@service)

        first_client = create_client('first_client', :requested_period => 42)
        @service.add_client(first_client)
        dummy_loop.expects(:period=).with(42)
        @service.poll

        second_client = create_client('second_client', :requested_period => 7)
        @service.add_client(second_client)
        dummy_loop.expects(:period=).with(7)
        @service.poll
      end

      def test_service_increments_client_poll_counts
        three = create_client('3')
        three.stubs(:finished?).returns(false, false, false, true)

        three.expects(:increment_poll_count).times(3)
        @service.add_client(three)
        @service.wait
      end

      def test_poll_records_polling_time
        freeze_time
        client = create_client('polling_time')

        def client.increment_poll_count
          advance_time(5.0)
        end

        @service.add_client(client)

        @service.wait
        expected = { :call_count => 1, :total_call_time => 5}
        assert_metrics_recorded(
          { 'Supportability/ThreadProfiler/PollingTime' => expected }
        )
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

      def test_adding_clients_is_thread_safe
        propagating_worker_loop = NewRelic::Agent::WorkerLoop.new(:propagate_errors => true)

        @service.stubs(:worker_loop).returns(propagating_worker_loop)
        long_client = create_client('long_client', :finished? => false)

        @service.add_client(long_client)

        1000.times do
          @service.add_client(create_client('short_client', :requested_period => 0))
        end
      end
    end

  end
end
