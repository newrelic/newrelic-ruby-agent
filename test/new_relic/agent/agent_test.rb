# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/commands/thread_profiler'

module NewRelic
  module Agent
    class AgentTest < Test::Unit::TestCase

      def setup
        super
        @agent = NewRelic::Agent::Agent.new
        @agent.service = default_service
        @agent.agent_command_router.stubs(:new_relic_service).returns(@agent.service)
        @agent.stubs(:start_worker_thread)
      end

      #
      # Helpers
      #

      def with_profile(opts)
        profile = NewRelic::Agent::Threading::ThreadProfile.new(create_agent_command)
        profile.aggregate(["chunky.rb:42:in `bacon'"], profile.traces[:other])
        profile.instance_variable_set(:@finished, opts[:finished])

        @agent.thread_profiler.instance_variable_set(:@profile, profile)
        profile
      end

      #
      # Tests
      #

      def test_after_fork_reporting_to_channel
        @agent.stubs(:connected?).returns(true)
        @agent.after_fork(:report_to_channel => 123)
        assert(@agent.service.kind_of?(NewRelic::Agent::PipeService),
               'Agent should use PipeService when directed to report to pipe channel')
        NewRelic::Agent::PipeService.any_instance.expects(:shutdown).never
        assert_equal 123, @agent.service.channel_id
      end

      def test_after_fork_should_close_pipe_if_parent_not_connected
        pipe = mock
        pipe.expects(:after_fork_in_child)
        pipe.expects(:close)
        pipe.stubs(:parent_pid).returns(:digglewumpus)
        dummy_channels = { 123 => pipe }
        NewRelic::Agent::PipeChannelManager.stubs(:channels).returns(dummy_channels)

        @agent.stubs(:connected?).returns(false)
        @agent.after_fork(:report_to_channel => 123)
        assert(@agent.disconnected?)
      end

      def test_after_fork_should_replace_stats_engine
        with_config(:monitor_mode => true) do
          @agent.stubs(:connected?).returns(true)
          old_engine = @agent.stats_engine

          @agent.after_fork(:report_to_channel => 123)

          assert old_engine != @agent.stats_engine, "Still got our old engine around!"
        end
      end

      def test_after_fork_should_reset_errors_collected
        with_config(:monitor_mode => true) do
          @agent.stubs(:connected?).returns(true)

          errors = []
          errors << NewRelic::NoticedError.new("", {}, Exception.new("boo"))
          @agent.merge_data_from([{}, [], errors])

          @agent.after_fork(:report_to_channel => 123)

          assert_equal 0, @agent.error_collector.errors.length, "Still got errors collected in parent"
        end
      end

      def test_transmit_data_should_emit_before_harvest_event
        got_it = false
        @agent.events.subscribe(:before_harvest) { got_it = true }
        @agent.instance_eval { transmit_data }
        assert(got_it)
      end

      def test_transmit_data_should_transmit
        @agent.service.expects(:metric_data).at_least_once
        @agent.instance_eval { transmit_data }
      end

      def test_transmit_data_should_use_one_http_handle_per_harvest
        @agent.service.expects(:session).once
        @agent.instance_eval { transmit_data }
      end

      def test_transmit_data_should_close_explain_db_connections
        NewRelic::Agent::Database.expects(:close_connections)
        @agent.instance_eval { transmit_data }
      end

      def test_transmit_data_should_handle_eoferror
        @agent.service.stubs(:metric_data).raises(EOFError)
        expects_no_logging(:error)
        expects_logging(:warn, regexp_matches(/EOFError/))
        expects_logging(:debug, is_a(EOFError))
        @agent.instance_eval { transmit_data }
      end

      def test_harvest_transaction_traces
        assert_equal([], @agent.send(:harvest_transaction_traces), 'should return transaction traces')
      end

      def test_harvest_and_send_slowest_sample
        with_config(:'transaction_tracer.explain_threshold' => 2,
                    :'transaction_tracer.explain_enabled' => true,
                    :'transaction_tracer.record_sql' => 'raw') do
          trace = stub('transaction trace', :force_persist => true,
                       :truncate => 4000)
          trace.expects(:prepare_to_send).with(:record_sql => :raw,
                                               :explain_sql => 2,
                                               :keep_backtraces => true)
          @agent.instance_variable_set(:@traces, [ trace ])
          @agent.send :harvest_and_send_slowest_sample
        end
      end

      def test_graceful_shutdown_ends_thread_profiling
        @agent.thread_profiler.expects(:stop).once
        @agent.stubs(:connected?).returns(true)
        @agent.send(:graceful_disconnect)
      end

      def test_harvest_and_send_thread_profile
        profile = with_profile(:finished => true)
        @agent.service.expects(:profile_data).with(any_parameters)
        @agent.send(:harvest_and_send_thread_profile, false)
      end

      def test_harvest_and_send_thread_profile_when_not_finished
        with_profile(:finished => false)
        @agent.service.expects(:profile_data).never
        @agent.send(:harvest_and_send_thread_profile, false)
      end

      def test_harvest_and_send_thread_profile_when_not_finished_but_disconnecting
        profile = with_profile(:finished => false)
        @agent.service.expects(:profile_data).with(any_parameters)
        @agent.send(:harvest_and_send_thread_profile, true)
      end

      def test_harvest_timeslice_data
        assert_equal({}, @agent.send(:harvest_timeslice_data),
                     'should return timeslice data')
      end

      # This test asserts nothing about correctness of logging data from multiple
      # threads, since the get_stats + record_data_point combo is not designed
      # to be thread-safe, but it does ensure that writes to the stats hash
      # via this path that happen concurrently with harvests will not cause
      # 'hash modified during iteration' errors.
      def test_harvest_timeslice_data_should_be_thread_safe
        threads = []
        nthreads = 10
        nmetrics = 100

        assert_nothing_raised do
          nthreads.times do |tid|
            t = Thread.new do
              nmetrics.times do |mid|
                @agent.stats_engine.get_stats("m#{mid}").record_data_point(1)
              end
            end
            t.abort_on_exception = true
            threads << t
          end

          100.times { @agent.send(:harvest_timeslice_data) }
          threads.each { |t| t.join }
        end
      end

      def test_harvest_errors
        assert_equal([], @agent.send(:harvest_errors), 'should return errors')
      end

      def test_handle_for_agent_commands
        @agent.service.expects(:get_agent_commands).returns([]).once
        @agent.send :handle_agent_commands
      end

      def test_merge_data_from_empty
        unsent_timeslice_data = mock('unsent timeslice data')
        unsent_errors = mock('unsent errors')
        unsent_traces = mock('unsent traces')
        @agent.instance_eval {
          @unsent_errors = unsent_errors
          @unsent_timeslice_data = unsent_timeslice_data
          @traces = unsent_traces
        }
        # nb none of the others should receive merge requests
        @agent.merge_data_from([{}])
      end

      def test_unsent_errors_size_empty
        @agent.instance_eval {
          @unsent_errors = nil
        }
        assert_equal(nil, @agent.unsent_errors_size)
      end

      def test_unsent_errors_size_with_errors
        @agent.instance_eval {
          @unsent_errors = ['an error']
        }
        assert_equal(1, @agent.unsent_errors_size)
      end

      def test_unsent_traces_size_empty
        @agent.instance_eval {
          @traces = nil
        }
        assert_equal(nil, @agent.unsent_traces_size)
      end

      def test_unsent_traces_size_with_traces
        @agent.instance_eval {
          @traces = ['a trace']
        }
        assert_equal(1, @agent.unsent_traces_size)
      end

      def test_unsent_timeslice_data_empty
        @agent.instance_eval {
          @unsent_timeslice_data = nil
        }
        assert_equal(0, @agent.unsent_timeslice_data, "should have zero timeslice data to start")
        assert_equal({}, @agent.instance_variable_get('@unsent_timeslice_data'), "should initialize the timeslice data to an empty hash if it is empty")
      end

      def test_unsent_timeslice_data_with_errors
        @agent.instance_eval {
          @unsent_timeslice_data = {:key => 'value'}
        }
        assert_equal(1, @agent.unsent_timeslice_data, "should have the key from above")
      end

      def test_merge_data_traces
        unsent_traces = mock('unsent traces')
        @agent.instance_eval {
          @traces = unsent_traces
        }
        unsent_traces.expects(:+).with([1,2,3])
        @agent.merge_data_from([{}, [1,2,3], []])
      end

      def test_merge_data_from_abides_by_error_queue_limit
        errors = []
        40.times { |i| errors << NewRelic::NoticedError.new("", {}, Exception.new("boo #{i}")) }

        @agent.merge_data_from([{}, [], errors])

        assert_equal 20, @agent.error_collector.errors.length

        # This method should NOT increment error counts, since that has already
        # been counted in the child
        assert_equal 0, @agent.stats_engine.get_stats("Errors/all").call_count
      end

      def test_connect_retries_on_timeout
        service = @agent.service
        def service.connect(opts={})
          unless @tried
            @tried = true
            raise Timeout::Error
          end
          nil
        end
        @agent.stubs(:connect_retry_period).returns(0)
        @agent.send(:connect)
        assert(@agent.connected?)
      end

      def test_connect_does_not_retry_if_keep_retrying_false
        @agent.service.expects(:connect).once.raises(Timeout::Error)
        @agent.send(:connect, :keep_retrying => false)
        assert(@agent.disconnected?)
      end

      def test_connect_does_not_retry_on_license_error
        @agent.service.expects(:connect).raises(NewRelic::Agent::LicenseException)
        @agent.send(:connect)
        assert(@agent.disconnected?)
      end

      def test_connect_does_not_reconnect_by_default
        @agent.stubs(:connected?).returns(true)
        @agent.service.expects(:connect).never
        @agent.send(:connect)
      end

      def test_connect_does_not_reconnect_if_disconnected
        @agent.stubs(:disconnected?).returns(true)
        @agent.service.expects(:connect).never
        @agent.send(:connect)
      end

      def test_connect_does_reconnect_if_forced
        @agent.stubs(:connected?).returns(true)
        @agent.service.expects(:connect)
        @agent.send(:connect, :force_reconnect => true)
      end

      def test_defer_start_if_resque_dispatcher_and_channel_manager_isnt_started
        NewRelic::Agent::PipeChannelManager.listener.expects(:started?).returns(false)

        # :send_data_on_exit setting to avoid setting an at_exit
        with_config( :send_data_on_exit => false, :dispatcher => :resque ) do
          @agent.start
        end

        assert !@agent.started?
      end

      def test_doesnt_defer_start_if_resque_dispatcher_and_channel_manager_started
        NewRelic::Agent::PipeChannelManager.listener.expects(:started?).returns(true)

        # :send_data_on_exit setting to avoid setting an at_exit
        with_config( :send_data_on_exit => false, :dispatcher => :resque ) do
          @agent.start
        end

        assert @agent.started?
      end

      def test_defer_start_if_no_application_name_configured
        logdev = with_array_logger( :error ) do
          with_config( :app_name => false ) do
            @agent.start
          end
        end
        logmsg = logdev.array.first.gsub(/\n/, '')

        assert !@agent.started?, "agent was started"
        assert_match( /No application name configured/i, logmsg )
      end

      def test_synchronize_with_harvest
        lock = Mutex.new
        @agent.stubs(:harvest_lock).returns(lock)
        @agent.harvest_lock.lock

        started = false
        done = false

        thread = Thread.new do
          started = true
          @agent.synchronize_with_harvest do
            done = true
          end
        end

        until started do
          sleep(0.001)
        end
        assert !done

        @agent.harvest_lock.unlock
        thread.join

        assert done
      end

    end


    class AgentStartingTest < Test::Unit::TestCase
      def test_no_service_if_not_monitoring
        with_config(:monitor_mode => false) do
          agent = NewRelic::Agent::Agent.new
          assert_nil agent.service
        end
      end

      def test_abides_by_disabling_harvest_thread
        with_config(:disable_harvest_thread => true) do
          threads_before = Thread.list.length

          agent = NewRelic::Agent::Agent.new
          agent.send(:start_worker_thread)

          assert_equal threads_before, Thread.list.length
        end
      end

    end
  end
end
