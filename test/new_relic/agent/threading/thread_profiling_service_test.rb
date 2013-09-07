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
        @service = ThreadProfilingService.new
        super
      end

      def teardown
        @service.stop
        super
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

        carebear = mock('carebear')
        carebear.expects(:aggregate).with(faketrace, :request)
        carebear.expects(:aggregate).with(alsofaketrace, :differenter_request)
        carebear.stubs(:finished?).returns(false, true)

        @service.period = 0
        @service.add_client(carebear)
        @service.wait
      end

    end
  end
end
