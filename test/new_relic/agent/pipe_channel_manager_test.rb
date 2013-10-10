# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'timeout'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))
require 'new_relic/agent/pipe_channel_manager'

class NewRelic::Agent::PipeChannelManagerTest < Test::Unit::TestCase
  include TransactionSampleTestHelper

  def setup
    @test_config = { :developer_mode => true }
    NewRelic::Agent.agent.reset_stats
    NewRelic::Agent.config.apply_config(@test_config)
    NewRelic::Agent::PipeChannelManager.listener.close_all_pipes
    NewRelic::Agent.manual_start
    NewRelic::Agent::TransactionState.clear
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

      listener = start_listener_with_pipe(666)

      pid = Process.fork do
        NewRelic::Agent.after_fork
        new_engine = NewRelic::Agent::StatsEngine.new
        new_engine.get_stats_no_scope(metric).record_data_point(2.0)
        listener.pipes[666].write(:stats => new_engine.harvest)
      end
      Process.wait(pid)
      listener.stop

      assert_equal(3.0, engine.lookup_stats(metric).total_call_time)
      engine.reset_stats
    end

    def test_listener_merges_transaction_traces
      sampler = NewRelic::Agent.agent.transaction_sampler
      sample = run_sample_trace_on(sampler)
      assert_equal(1, sampler.count)

      listener = start_listener_with_pipe(667)
      pid = Process.fork do
        NewRelic::Agent.after_fork
        with_config(:'transaction_tracer.transaction_threshold' => 0.0) do
          sample = run_sample_trace_on(sampler)
          listener.pipes[667].write(:transaction_traces => sampler.harvest)
        end
      end
      Process.wait(pid)
      listener.stop

      assert_equal(2, sampler.count)
    end

    def test_listener_merges_error_traces
      sampler = NewRelic::Agent.agent.error_collector
      sampler.errors.clear
      sampler.notice_error(Exception.new("message"), :uri => '/myurl/',
                           :metric => 'path', :referer => 'test_referer',
                           :request_params => {:x => 'y'})
      NewRelic::Agent.agent.merge_data_from([nil, nil, sampler.errors])

      assert_equal(1, NewRelic::Agent.agent.error_collector.errors.size)

      listener = start_listener_with_pipe(668)

      pid = Process.fork do
        NewRelic::Agent.after_fork
        new_sampler = NewRelic::Agent::ErrorCollector.new
        new_sampler.notice_error(Exception.new("new message"), :uri => '/myurl/',
                                 :metric => 'path', :referer => 'test_referer',
                                 :request_params => {:x => 'y'})
        listener.pipes[668].write(:error_traces => new_sampler.harvest_errors)
      end
      Process.wait(pid)
      listener.stop

      assert_equal(2, NewRelic::Agent.agent.error_collector.errors.size)
    end

    def pipe_finished?(id)
      (!NewRelic::Agent::PipeChannelManager.channels[id] ||
        NewRelic::Agent::PipeChannelManager.channels[id].closed?)
    end

    def assert_pipe_finished(id)
      assert(pipe_finished?(id),
        "Expected pipe with ID #{id} to be nil or closed")
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
      assert_nothing_raised do
        pid = Process.fork do
          listener.pipes[670].in << 'some unloadable garbage'
        end
        Process.wait(pid)
        listener.stop
      end
    end
  end

  def start_listener_with_pipe(pipe_id)
    listener = NewRelic::Agent::PipeChannelManager.listener
    listener.start
    listener.register_pipe(pipe_id)
    listener
  end
end
