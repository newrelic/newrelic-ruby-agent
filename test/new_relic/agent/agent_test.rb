require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/thread_profiler'

module NewRelic
  module Agent
    class AgentTest < Test::Unit::TestCase
      def setup
        super
        @agent = NewRelic::Agent::Agent.new
        @agent.service = NewRelic::FakeService.new
      end

      def test_after_fork_reporting_to_channel
        @agent.after_fork(:report_to_channel => 123)
        assert(@agent.service.kind_of?(NewRelic::Agent::PipeService),
               'Agent should use PipeService when directed to report to pipe channel')
        assert_equal 123, @agent.service.channel_id
      end

      def test_transmit_data_should_transmit
        @agent.instance_eval { transmit_data }
        assert @agent.service.agent_data.any?
      end

      def test_transmit_data_should_close_explain_db_connections
        NewRelic::Agent::Database.expects(:close_connections)
        @agent.instance_eval { transmit_data }
      end

      def test_transmit_data_should_not_close_db_connections_if_forked
        NewRelic::Agent::Database.expects(:close_connections).never
        @agent.after_fork
        @agent.instance_eval { transmit_data }
      end

      def test_serialize
        assert_equal([{}, [], []], @agent.send(:serialize), "should return nil when shut down")
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
        @agent.instance_variable_set(:@connected, true)

        @agent.send(:graceful_disconnect)
      end

      def test_harvest_and_send_thread_profile
        profile = with_profile(:finished => true)
        @agent.send(:harvest_and_send_thread_profile, false)

        assert_equal([profile],
                    @agent.service.agent_data \
                      .find{|data| data.action == :profile_data}.params)
      end

      def test_harvest_and_send_thread_profile_when_not_finished
        with_profile(:finished => false)
        @agent.send(:harvest_and_send_thread_profile, false)

        assert_nil @agent.service.agent_data.find{|data| data.action == :profile_data}
      end

      def test_harvest_and_send_thread_profile_when_not_finished_but_disconnecting
        profile = with_profile(:finished => false)
        @agent.send(:harvest_and_send_thread_profile, true)

        assert_equal([profile],
                     @agent.service.agent_data \
                       .find{|data| data.action == :profile_data}.params)
      end

      def with_profile(opts)
        profile = NewRelic::Agent::ThreadProfile.new(-1, 0, 0, true)
        profile.aggregate(["chunky.rb:42:in `bacon'"], profile.traces[:other])
        profile.instance_variable_set(:@finished, opts[:finished])

        @agent.thread_profiler.instance_variable_set(:@profile, profile)
        profile
      end

      def test_harvest_timeslice_data
        assert_equal({}, @agent.send(:harvest_timeslice_data),
                     'should return timeslice data')
      end

      def test_harvest_timelice_data_should_be_thread_safe
        2000.times do |i|
          @agent.stats_engine.stats_hash[i.to_s] = NewRelic::StatsBase.new
        end

        harvest = Thread.new("Harvesting Test run timeslices") do
          @agent.send(:harvest_timeslice_data)
        end

        app = Thread.new("Harvesting Test Modify stats_hash") do
          200.times do |i|
            @agent.stats_engine.stats_hash["a#{i}"] = NewRelic::StatsBase.new
          end
        end

        assert_nothing_raised do
          [app, harvest].each{|t| t.join}
        end
      end

      def test_harvest_errors
        assert_equal([], @agent.send(:harvest_errors), 'should return errors')
      end

      def test_check_for_agent_commands
        @agent.send :check_for_agent_commands
        assert_equal(1, @agent.service.calls_for(:get_agent_commands).size)
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

      def test_merge_data_from_all_three_empty
        unsent_timeslice_data = mock('unsent timeslice data')
        unsent_errors = mock('unsent errors')
        unsent_traces = mock('unsent traces')
        @agent.instance_eval {
          @unsent_errors = unsent_errors
          @unsent_timeslice_data = unsent_timeslice_data
          @traces = unsent_traces
        }
        unsent_traces.expects(:+).with([1,2,3])
        unsent_errors.expects(:+).with([4,5,6])
        @agent.merge_data_from([{}, [1,2,3], [4,5,6]])
      end

      def test_should_not_log_log_file_location_if_no_log_file
        NewRelic::Control.instance.stubs(:log_file).returns('/vasrkjn4b3b4')
        @agent.expects(:log).never
        @agent.notify_log_file_location
      end

      def test_fill_metric_id_cache_from_collect_response
        response = [[{"scope"=>"Controller/blogs/index", "name"=>"Database/SQL/other"}, 1328],
                    [{"scope"=>"", "name"=>"WebFrontend/QueueTime"}, 10],
                    [{"scope"=>"", "name"=>"ActiveRecord/Blog/find"}, 1017]]

        @agent.send(:fill_metric_id_cache, response)
        assert_equal 1328, @agent.metric_ids[MetricSpec.new('Database/SQL/other', 'Controller/blogs/index')]
        assert_equal 10,   @agent.metric_ids[MetricSpec.new('WebFrontend/QueueTime')]
        assert_equal 1017, @agent.metric_ids[MetricSpec.new('ActiveRecord/Blog/find')]
      end
    end
  end
end
