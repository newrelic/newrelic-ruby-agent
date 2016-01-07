# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'timeout'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))
require 'new_relic/agent/pipe_channel_manager'
require 'new_relic/agent/transaction_event_primitive'

class NewRelic::Agent::PipeChannelManagerTest < Minitest::Test
  include TransactionSampleTestHelper

  def setup
    @test_config = { :monitor_mode => true }
    NewRelic::Agent.agent.drop_buffered_data
    NewRelic::Agent.config.add_config_for_testing(@test_config)

    listener = NewRelic::Agent::PipeChannelManager::Listener.new
    NewRelic::Agent::PipeChannelManager.instance_variable_set(:@listener, listener)

    NewRelic::Agent.manual_start
    NewRelic::Agent::TransactionState.tl_clear_for_testing
  end

  def teardown
    NewRelic::Agent::PipeChannelManager.listener.close_all_pipes
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

      assert_metrics_recorded(metric => { :total_call_time => 3.0 })
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
      NewRelic::Agent.agent.merge_data_for_endpoint(:error_data, sampler.error_trace_aggregator.harvest!)

      errors = NewRelic::Agent.agent.error_collector.error_trace_aggregator.instance_variable_get :@errors
      assert_equal(1, errors.size)

      start_listener_with_pipe(668)

      run_child(668) do
        NewRelic::Agent.after_fork
        new_sampler = NewRelic::Agent::ErrorCollector.new
        new_sampler.notice_error(Exception.new("new message"), :uri => '/myurl/',
                                 :metric => 'path', :referer => 'test_referer',
                                 :request_params => {:x => 'y'})
        service = NewRelic::Agent::PipeService.new(668)
        service.error_data(new_sampler.error_trace_aggregator.harvest!)
      end
      errors = NewRelic::Agent.agent.error_collector.error_trace_aggregator.instance_variable_get :@errors
      assert_equal(2, errors.size)
    end

    def test_listener_merges_analytics_events
      transaction_event_aggregator = NewRelic::Agent.agent.transaction_event_aggregator
      reset_lifetime_counts! transaction_event_aggregator

      start_listener_with_pipe(699)
      NewRelic::Agent.agent.stubs(:connected?).returns(true)
      run_child(699) do
        NewRelic::Agent.after_fork(:report_to_channel => 699)
        transaction_event_aggregator.append NewRelic::Agent::TransactionEventPrimitive.create({
          :start_timestamp => Time.now,
          :name => 'whatever',
          :duration => 10,
          :type => :controller
        })
        NewRelic::Agent.agent.send(:transmit_event_data)
      end

      _, samples = transaction_event_aggregator.harvest!

      assert_equal(1, samples.size)
      assert_lifetime_counts(transaction_event_aggregator, 1)
    end

    def test_listener_merges_error_events
      error_event_aggregator = NewRelic::Agent.agent.error_collector.error_event_aggregator
      reset_lifetime_counts! error_event_aggregator

      sampler = NewRelic::Agent.agent.error_collector
      sampler.notice_error(Exception.new("message"), :uri => '/myurl/',
                           :metric => 'path', :referer => 'test_referer',
                           :request_params => {:x => 'y'})

      start_listener_with_pipe(668)

      run_child(668) do
        NewRelic::Agent.after_fork
        new_sampler = NewRelic::Agent::ErrorCollector.new
        new_sampler.notice_error(Exception.new("new message"), :uri => '/myurl/',
                                 :metric => 'path', :referer => 'test_referer',
                                 :request_params => {:x => 'y'})
        service = NewRelic::Agent::PipeService.new(668)
        service.error_event_data(new_sampler.error_event_aggregator.harvest!)
      end
      _, errors = error_event_aggregator.harvest!
      assert_equal(2, errors.size)
      assert_lifetime_counts(error_event_aggregator, 2)
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

  def test_listener_pipes_race_condition
    # 1.8.7 doesn't have easy singleton_class access, but also doesn't have
    # races thanks to green threads and the GIL, so pitch it!
    return if RUBY_VERSION < "1.9.2"

    begin
      listener = NewRelic::Agent::PipeChannelManager.listener
      listener.instance_variable_set(:@select_timeout, 0.00001)
      listener.start

      listener.register_pipe(0)
      pipe_out = listener.pipes[0].out

      mutex = Mutex.new
      mutex.lock
      tried_to_close = false
      pipe_out.singleton_class.send(:define_method, :closed?, Proc.new do
        tried_to_close = true
        mutex.synchronize do
        end
      end)

      # Make sure we're actually paused in closed? call
      until tried_to_close
      end

      t = Thread.new do
        listener.register_pipe(1)
      end

      mutex.unlock
      t.join
    ensure
      listener.close_all_pipes
      listener.stop
    end
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

  def assert_lifetime_counts container, value
    buffer = container.instance_variable_get :@buffer
    assert_equal value, buffer.captured_lifetime
    assert_equal value, buffer.seen_lifetime
  end

  def reset_lifetime_counts! container
    buffer = container.instance_variable_get :@buffer
    buffer.instance_variable_set :@captured_lifetime, 0
    buffer.instance_variable_set :@seen_lifetime, 0
  end
end
