# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

require 'new_relic/agent/threading/thread_profiling_service'
require 'new_relic/agent/threading/threaded_test_case'

if NewRelic::Agent::Commands::ThreadProfiler.is_supported?

  module NewRelic::Agent::Threading
    class ThreadProfilingServiceTest < ThreadedTestCase
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
        client.stubs(:finished?).returns(false, true)
        client
      end

      def test_starts_when_the_first_client_is_added
        assert_false @service.running?

        first_client = @service.add_client(mock)

        assert @service.running?
      end

      def test_stops_without_clients
        first_client = @service.add_client(mock)

        assert_true @service.running?

        @service.remove_client(first_client)
        assert_false @service.running?
      end

      def test_runs_until_all_clients_have_been_removed
        first_client = @service.add_client(mock)
        second_client = @service.add_client(mock)
        assert_true @service.running?

        @service.remove_client(first_client)
        assert @service.running?

        @service.remove_client(second_client)
        assert_false @service.running?
      end

      def test_start_sets_running_to_true
        @service.start
        assert @service.running?
      end

      def test_stop_sets_running_to_false
        @service.stop
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

      def test_minimum_client_period_determines_the_minimum_period_of_all_clients
        @service.stubs(:worker_loop).returns(stub(:run => nil, :stop => nil))
        @service.add_client(create_client(requested_period: 42))
        @service.add_client(create_client(requested_period: 77))
        assert_equal 42, @service.minimum_client_period
      end

      def test_poll_adjusts_worker_loop_period_to_minimum_client_period
        dummy_loop = stub(:run => nil, :stop => nil)
        @service.stubs(:worker_loop).returns(dummy_loop)

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
        @service.add_client(client)

        def client.increment_poll_count
          advance_time(5.0)
        end

        @service.wait
        expected = { :call_count => 1, :total_call_time => 5}
        assert_metrics_recorded(
          { 'Supportability/ThreadProfiler/PollingTime' => expected }
        )
      end

    end
  end
end
