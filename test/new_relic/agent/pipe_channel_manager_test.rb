# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'timeout'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))
require 'new_relic/agent/pipe_channel_manager'

class NewRelic::Agent::PipeChannelManagerTest < Minitest::Test
  include TransactionSampleTestHelper

  def setup
    @test_config = { :developer_mode => true }
    NewRelic::Agent.agent.drop_buffered_data
    NewRelic::Agent.config.add_config_for_testing(@test_config)
    NewRelic::Agent::PipeChannelManager.listener.close_all_pipes
    NewRelic::Agent.manual_start
    NewRelic::Agent::TransactionState.tl_clear_for_testing
  end

  def teardown
    NewRelic::Agent::PipeChannelManager.listener.stop
    NewRelic::Agent.shutdown
    NewRelic::Agent.config.remove_config(@test_config)
  end

  def test_registering_a_pipe
    NewRelic::Agent::PipeChannelManager.listener.wake.in.expects(:<<).with('.')
    NewRelic::Agent::PipeChannelManager.register_report_channel(1)
    pipe = NewRelic::Agent::PipeChannelManager.channels[1]

    assert pipe.out.kind_of?(IO)
    assert pipe.in.kind_of?(IO)

    NewRelic::Agent::PipeChannelManager.listener.close_all_pipes
  end

  if NewRelic::LanguageSupport.can_fork? && !NewRelic::LanguageSupport.using_version?('1.9.1')
    def test_listener_merges_timeslice_metrics
      metric = 'Custom/test/method'
      engine = NewRelic::Agent.agent.stats_engine
      engine.get_stats_no_scope(metric).record_data_point(1.0)

      start_listener_with_pipe(666)

      run_child(666) do
        NewRelic::Agent.after_fork
        new_engine = NewRelic::Agent::StatsEngine.new
        new_engine.get_stats_no_scope(metric).record_data_point(2.0)
        service = NewRelic::Agent::PipeService.new(666)
        service.metric_data(new_engine.harvest!)
      end

      assert_equal(3.0, engine.lookup_stats(metric).total_call_time)
      engine.reset!
    end

    def test_listener_merges_transaction_traces
      sampler = NewRelic::Agent.agent.transaction_sampler
      sample = run_sample_trace
      assert_equal(1, sampler.count)

      start_listener_with_pipe(667)
      run_child(667) do
        NewRelic::Agent.after_fork
        with_config(:'transaction_tracer.transaction_threshold' => 0.0) do
          sample = run_sample_trace
          service = NewRelic::Agent::PipeService.new(667)
          service.transaction_sample_data(sampler.harvest!)
        end
      end

      assert_equal(2, sampler.count)
    end

    def test_listener_merges_error_traces
      sampler = NewRelic::Agent.agent.error_collector
      sampler.notice_error(Exception.new("message"), :uri => '/myurl/',
                           :metric => 'path', :referer => 'test_referer',
                           :request_params => {:x => 'y'})
      NewRelic::Agent.agent.merge_data_for_endpoint(:error_data, sampler.errors)

      assert_equal(1, NewRelic::Agent.agent.error_collector.errors.size)

      start_listener_with_pipe(668)

      run_child(668) do
        NewRelic::Agent.after_fork
        new_sampler = NewRelic::Agent::ErrorCollector.new
        new_sampler.notice_error(Exception.new("new message"), :uri => '/myurl/',
                                 :metric => 'path', :referer => 'test_referer',
                                 :request_params => {:x => 'y'})
        service = NewRelic::Agent::PipeService.new(668)
        service.error_data(new_sampler.harvest!)
      end

      assert_equal(2, NewRelic::Agent.agent.error_collector.errors.size)
    end

    def test_listener_merges_analytics_events
      request_sampler = NewRelic::Agent.agent.instance_variable_get(:@request_sampler)

      start_listener_with_pipe(699)
      NewRelic::Agent.agent.stubs(:connected?).returns(true)
      run_child(699) do
        NewRelic::Agent.after_fork(:report_to_channel => 699)
        request_sampler.on_transaction_finished({
          :start_timestamp => Time.now,
          :name => 'whatever',
          :duration => 10,
          :type => :controller
        })
        NewRelic::Agent.agent.send(:transmit_transaction_event_data)
      end

      assert_equal(1, request_sampler.samples.size)
    end

    def test_listener_merges_sql_traces
      sampler = NewRelic::Agent.agent.sql_sampler
      create_sql_sample(sampler)

      start_listener_with_pipe(667)
      run_child(667) do
        NewRelic::Agent.after_fork
        create_sql_sample(sampler)
        service = NewRelic::Agent::PipeService.new(667)
        service.sql_trace_data(sampler.harvest!)
      end

      assert_equal(2, sampler.harvest!.size)
    end

    def test_close_pipe_on_child_explicit_close
      listener = start_listener_with_pipe(669)
      pid = Process.fork do
        NewRelic::Agent::PipeService.new(669)
      end
      Process.wait(pid)
      listener.stop_listener_thread
      assert_pipe_finished(669)
    end

    def test_close_pipe_on_child_exit
      listener = start_listener_with_pipe(669)
      pid = Process.fork do
        NewRelic::Agent::PipeService.new(669)
        exit!
      end
      Process.wait(pid)
      listener.stop_listener_thread
      assert_pipe_finished(669)
    end

    def test_manager_does_not_crash_when_given_bad_data
      listener = start_listener_with_pipe(670)
      pid = Process.fork do
        listener.pipes[670].in << 'some unloadable garbage'
      end
      Process.wait(pid)
      listener.stop
    end

    def test_manager_does_not_crash_when_given_unmarshallable_junk
      listener = start_listener_with_pipe(671)
      expects_logging(:error, any_parameters)

      pid = Process.fork do
        listener.pipes[671].write("\x00")
      end
      Process.wait(pid)
      listener.stop
    end

    def pipe_finished?(id)
      (!NewRelic::Agent::PipeChannelManager.channels[id] ||
        NewRelic::Agent::PipeChannelManager.channels[id].closed?)
    end

    def assert_pipe_finished(id)
      assert(pipe_finished?(id),
        "Expected pipe with ID #{id} to be nil or closed")
    end

    def create_sql_sample(sampler)
      state = NewRelic::Agent::TransactionState.tl_get
      sampler.on_start_transaction(state, Time.now)
      sampler.notice_sql("SELECT * FROM table", "ActiveRecord/Widgets/find", nil, 100, state)
      sampler.on_finishing_transaction(state, 'noodles', Time.now)
    end
  end

  def start_listener_with_pipe(pipe_id)
    listener = NewRelic::Agent::PipeChannelManager.listener
    listener.start
    listener.register_pipe(pipe_id)
    listener
  end

  def test_pipe_read_length_failure
    write_pipe = stub(:set_encoding => nil, :closed? => false, :close => nil)

    # If we only read three bytes, it isn't valid.
    # We can't tell whether any four bytes or more are a "good" length or not.
    read_pipe = stub(:read => "jrc")
    IO.stubs(:pipe).returns([read_pipe, write_pipe])

    # Includes the failed bytes
    expects_logging(:error, includes("[6a 72 63]"))

    pipe = NewRelic::Agent::PipeChannelManager::Pipe.new
    assert_nil pipe.read
  end

  def test_pipe_read_length_nil_fails
    write_pipe = stub(:set_encoding => nil, :closed? => false, :close => nil)

    # No length at all returned on pipe, also a failure.
    read_pipe = stub(:read => nil)
    IO.stubs(:pipe).returns([read_pipe, write_pipe])

    pipe = NewRelic::Agent::PipeChannelManager::Pipe.new
    assert_nil pipe.read
  end

  def run_child(channel_id)
    pid = Process.fork do
      yield
    end

    Process.wait(pid)
    until pipe_finished?(channel_id)
      sleep 0.01
    end
  end
end
