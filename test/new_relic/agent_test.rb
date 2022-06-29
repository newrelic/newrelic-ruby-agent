# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../test_helper'
require 'ostruct'

module NewRelic
  # mostly this class just passes through to the active agent
  # through the agent method or the control instance through
  # NewRelic::Control.instance . But it's nice to make sure.
  class MainAgentTest < Minitest::Test
    include NewRelic::Agent::MethodTracer

    def setup
      NewRelic::Agent.drop_buffered_data
      NewRelic::Agent.reset_config
      NewRelic::Agent.instance.stubs(:start_worker_thread)
    end

    def teardown
      NewRelic::Agent::Tracer.clear_state
    end

    def test_shutdown
      mock_agent = mocked_agent
      mock_engine = mock
      mock_stats = mock
      mock_agent.expects(:shutdown)
      mock_agent.expects(:stats_engine).returns(mock_engine)
      mock_engine.expects(:tl_record_unscoped_metrics).with('Supportability/API/shutdown').yields(mock_stats)
      mock_stats.expects(:increment_count)
      NewRelic::Agent.shutdown
    end

    def test_shutdown_removes_manual_startup_config
      NewRelic::Agent.manual_start(:monitor_mode => true, :license_key => "a" * 40, :some_absurd_setting => true)
      assert NewRelic::Agent.config[:some_absurd_setting]
      NewRelic::Agent.shutdown
      assert !NewRelic::Agent.config[:some_absurd_setting]
    end

    def test_shutdown_removes_server_config
      NewRelic::Agent.manual_start(:monitor_mode => true, :license_key => "a" * 40)
      response_handler = ::NewRelic::Agent::Connect::ResponseHandler.new(
        NewRelic::Agent.instance, NewRelic::Agent.config
      )
      response_handler.configure_agent(
        'agent_config' => {'data_report_period' => 10}
      )
      assert_equal 10, NewRelic::Agent.config[:data_report_period]
      NewRelic::Agent.shutdown
      assert_equal 60, NewRelic::Agent.config[:data_report_period]
    end

    def test_configure_agent_applied_server_side_config
      response_handler = ::NewRelic::Agent::Connect::ResponseHandler.new(
        NewRelic::Agent.instance, NewRelic::Agent.config
      )
      with_config_low_priority({
        :'transction_tracer.enabled' => true,
        :'error_collector.enabled' => true
      }) do
        response_handler.configure_agent(
          'agent_config' => {'transaction_tracer.enabled' => false},
          'collect_errors' => false
        )
        refute NewRelic::Agent.config[:'transaction_tracer.enabled']
        refute NewRelic::Agent.config[:'error_collector.enabled']
      end
    end

    def test_after_fork
      mock_agent = mocked_agent
      mock_engine = mock
      mock_stats = mock
      mock_agent.expects(:after_fork).with({})
      mock_agent.expects(:stats_engine).returns(mock_engine)
      mock_engine.expects(:tl_record_unscoped_metrics).yields(mock_stats)
      mock_stats.expects(:increment_count)
      NewRelic::Agent.after_fork
    end

    def test_manual_start_default
      mock_control = mocked_control
      mock_control.expects(:init_plugin).with({:agent_enabled => true, :sync_startup => true})
      NewRelic::Agent.manual_start
    end

    def test_manual_start_with_opts
      mock_control = mocked_control
      mock_control.expects(:init_plugin).with({:agent_enabled => true, :sync_startup => false})
      NewRelic::Agent.manual_start(:sync_startup => false)
    end

    def test_manual_start_starts_channel_listener
      NewRelic::Agent::PipeChannelManager.listener.expects(:start).at_least_once
      NewRelic::Agent.manual_start(:start_channel_listener => true)
      NewRelic::Agent.shutdown
    end

    def test_manual_start_kicks_dependency_check_again
      with_config(:monitor_mode => true, :license_key => "a" * 40, :sync_startup => true) do
        NewRelic::Agent.manual_start
        assert NewRelic::Agent.instance.started?

        NewRelic::Control.instance.stubs(:init_config)
        DependencyDetection.expects(:detect!).once

        NewRelic::Agent.manual_start
      end
      NewRelic::Agent.shutdown
    end

    def test_agent_logs_warning_when_not_started
      with_unstarted_agent do
        expects_logging(:warn, includes("hasn't been started"))
        NewRelic::Agent.agent
      end
    end

    def test_agent_can_shut_down_when_not_started
      with_unstarted_agent do
        NewRelic::Agent.shutdown
      end
    end

    def test_agent_when_started
      old_agent = NewRelic::Agent.agent
      NewRelic::Agent.instance_eval { @agent = 'not nil' }
      assert_equal('not nil', NewRelic::Agent.agent, "should return the value from @agent")
      NewRelic::Agent.instance_eval { @agent = old_agent }
    end

    def test_is_sql_recorded_true
      NewRelic::Agent::Tracer.state.record_sql = true
      assert_equal(true, NewRelic::Agent.tl_is_sql_recorded?, 'should be true since the thread local is set')
    end

    def test_is_sql_recorded_blank
      NewRelic::Agent::Tracer.state.record_sql = nil
      assert_equal(true, NewRelic::Agent.tl_is_sql_recorded?, 'should be true since the thread local is not set')
    end

    def test_is_sql_recorded_false
      NewRelic::Agent::Tracer.state.record_sql = false
      assert_equal(false, NewRelic::Agent.tl_is_sql_recorded?, 'should be false since the thread local is false')
    end

    def test_is_execution_traced_true
      NewRelic::Agent::Tracer.state.untraced = [true, true]
      assert_equal(true, NewRelic::Agent.tl_is_execution_traced?, 'should be true since the thread local is set')
    end

    def test_is_execution_traced_blank
      NewRelic::Agent::Tracer.state.untraced = nil
      assert_equal(true, NewRelic::Agent.tl_is_execution_traced?, 'should be true since the thread local is not set')
    end

    def test_is_execution_traced_empty
      NewRelic::Agent::Tracer.state.untraced = []
      assert_equal(true, NewRelic::Agent.tl_is_execution_traced?, 'should be true since the thread local is an empty array')
    end

    def test_is_execution_traced_false
      NewRelic::Agent::Tracer.state.untraced = [true, false]
      assert_equal(false, NewRelic::Agent.tl_is_execution_traced?, 'should be false since the thread local stack has the last element false')
    end

    def test_instance
      NewRelic::Agent.manual_start
      assert_equal(NewRelic::Agent.agent, NewRelic::Agent.instance, "should return the same agent for both identical methods")
      NewRelic::Agent.shutdown
    end

    def test_register_report_channel
      NewRelic::Agent.register_report_channel(:channel_id)
      assert NewRelic::Agent::PipeChannelManager.channels[:channel_id] \
        .kind_of?(NewRelic::Agent::PipeChannelManager::Pipe)
      NewRelic::Agent::PipeChannelManager.listener.close_all_pipes
    end

    def test_record_metric
      dummy_engine = NewRelic::Agent.agent.stats_engine
      dummy_engine.expects(:tl_record_unscoped_metrics).with('Supportability/API/record_metric')
      dummy_engine.expects(:tl_record_unscoped_metrics).with('foo', 12)
      NewRelic::Agent.record_metric('foo', 12)
    end

    def test_record_metric_accepts_hash
      dummy_engine = NewRelic::Agent.agent.stats_engine
      stats_hash = {
        :count => 12,
        :total => 42,
        :min => 1,
        :max => 5,
        :sum_of_squares => 999
      }
      expected_stats = NewRelic::Agent::Stats.new()
      expected_stats.call_count = 12
      expected_stats.total_call_time = 42
      expected_stats.total_exclusive_time = 42
      expected_stats.min_call_time = 1
      expected_stats.max_call_time = 5
      expected_stats.sum_of_squares = 999
      dummy_engine.expects(:tl_record_unscoped_metrics).with('Supportability/API/record_metric')
      dummy_engine.expects(:tl_record_unscoped_metrics).with('foo', expected_stats)
      NewRelic::Agent.record_metric('foo', stats_hash)
    end

    def test_record_metric_sets_default_hash_values_for_missing_keys
      dummy_engine = NewRelic::Agent.agent.stats_engine
      incomplete_stats_hash = {
        :count => 12,
        :max => 5,
        :sum_of_squares => 999
      }

      expected_stats = NewRelic::Agent::Stats.new()
      expected_stats.call_count = 12
      expected_stats.total_call_time = 0.0
      expected_stats.total_exclusive_time = 0.0
      expected_stats.min_call_time = 0.0
      expected_stats.max_call_time = 5
      expected_stats.sum_of_squares = 999

      dummy_engine.expects(:tl_record_unscoped_metrics).with('Supportability/API/record_metric')
      dummy_engine.expects(:tl_record_unscoped_metrics).with('foo', expected_stats)
      NewRelic::Agent.record_metric('foo', incomplete_stats_hash)
    end

    def test_increment_metric
      dummy_engine = NewRelic::Agent.agent.stats_engine
      dummy_stats = mock
      dummy_stats.expects(:increment_count)
      dummy_stats.expects(:increment_count).with(12)
      dummy_engine.expects(:tl_record_unscoped_metrics).with('Supportability/API/increment_metric').yields(dummy_stats)
      dummy_engine.expects(:tl_record_unscoped_metrics).with('foo').yields(dummy_stats)
      NewRelic::Agent.increment_metric('foo', 12)
    end

    class Transactor
      include NewRelic::Agent::Instrumentation::ControllerInstrumentation
      def txn
        yield
      end
      add_transaction_tracer :txn

      def task_txn
        yield
      end
      add_transaction_tracer :task_txn, :category => :task
    end

    def test_set_transaction_name
      engine = NewRelic::Agent.instance.stats_engine
      engine.reset!
      Transactor.new.txn do
        NewRelic::Agent.set_transaction_name('new_name')
      end
      assert_metrics_recorded(['Controller/new_name'])
    end

    def test_get_transaction_name_returns_nil_outside_transaction
      assert_nil NewRelic::Agent.get_transaction_name
    end

    def test_get_transaction_name_returns_the_default_txn_name
      engine = NewRelic::Agent.instance.stats_engine
      engine.reset!
      Transactor.new.txn do
        assert_equal 'NewRelic::MainAgentTest::Transactor/txn', NewRelic::Agent.get_transaction_name
      end
    end

    def test_get_transaction_name_returns_what_I_set
      engine = NewRelic::Agent.instance.stats_engine
      engine.reset!
      Transactor.new.txn do
        NewRelic::Agent.set_transaction_name('a_new_name')
        assert_equal 'a_new_name', NewRelic::Agent.get_transaction_name
      end
    end

    def test_get_txn_name_and_set_txn_name_preserves_category
      engine = NewRelic::Agent.instance.stats_engine
      engine.reset!
      Transactor.new.txn do
        NewRelic::Agent.set_transaction_name('a_new_name', :category => :task)
        new_name = NewRelic::Agent.get_transaction_name + "2"
        NewRelic::Agent.set_transaction_name(new_name)
      end
      assert_metrics_recorded 'OtherTransaction/Background/a_new_name2'
    end

    def test_set_transaction_name_applies_proper_scopes
      engine = NewRelic::Agent.instance.stats_engine
      engine.reset!
      Transactor.new.txn do
        trace_execution_scoped('Custom/something') {}
        NewRelic::Agent.set_transaction_name('new_name')
      end

      assert_metrics_recorded([
        'Custom/something',
        'Controller/new_name'
      ])
    end

    def test_set_transaction_name_sets_tt_name
      sampler = NewRelic::Agent.instance.transaction_sampler
      Transactor.new.txn do
        NewRelic::Agent.set_transaction_name('new_name')
      end
      assert_equal 'Controller/new_name', sampler.last_sample.transaction_name
    end

    def test_set_transaction_name_gracefully_fails_when_frozen
      engine = NewRelic::Agent.instance.stats_engine
      engine.reset!
      Transactor.new.txn do
        NewRelic::Agent::Transaction.tl_current.freeze_name_and_execute_if_not_ignored do
          NewRelic::Agent.set_transaction_name('new_name')
        end
      end
      refute_metrics_recorded('Controller/new_name')
    end

    def test_set_transaction_name_applies_category
      engine = NewRelic::Agent.instance.stats_engine
      engine.reset!
      Transactor.new.txn do
        NewRelic::Agent.set_transaction_name('new_name', :category => :task)
      end

      assert_metrics_recorded 'OtherTransaction/Background/new_name'

      Transactor.new.txn do
        NewRelic::Agent.set_transaction_name('new_name', :category => :rack)
      end

      assert_metrics_recorded 'Controller/Rack/new_name'

      Transactor.new.txn do
        NewRelic::Agent.set_transaction_name('new_name', :category => :sinatra)
      end

      assert_metrics_recorded 'Controller/Sinatra/new_name'
    end

    def test_set_transaction_name_uses_current_txn_category_default
      engine = NewRelic::Agent.instance.stats_engine
      engine.reset!
      Transactor.new.task_txn do
        NewRelic::Agent.set_transaction_name('new_name')
      end
      assert_metrics_recorded 'OtherTransaction/Background/new_name'
    end

    def setup_linking_metadata_stubs app_names, hostname, entity_guid = nil
      NewRelic::Agent.config.reset_to_defaults

      yaml_source = NewRelic::Agent::Configuration::YamlSource.new '', 'test'
      yaml_source[:app_name] = app_names
      NewRelic::Agent.config.replace_or_add_config yaml_source

      if entity_guid
        response_handler = NewRelic::Agent::Connect::ResponseHandler.new(Agent.instance, Agent.config)
        response_handler.configure_agent('entity_guid' => entity_guid)
      end

      NewRelic::Agent::Hostname.stubs(:get).returns(hostname)
    end

    def test_linking_metadata_before_connect
      setup_linking_metadata_stubs 'AppName', 'HostName'
      expected = {
        'entity.name' => 'AppName',
        'entity.type' => 'SERVICE',
        'hostname' => 'HostName'
      }

      assert_equal expected, NewRelic::Agent.linking_metadata
    end

    def test_linking_metadata_after_connect
      setup_linking_metadata_stubs 'AppName', 'HostName', 'EntityGUID'

      trace_id = nil
      span_id = nil
      linking_metadata = nil
      in_transaction do |txn|
        trace_id = txn.trace_id
        span_id = txn.current_segment.guid
        linking_metadata = NewRelic::Agent.linking_metadata
      end
      expected = {
        'entity.name' => 'AppName',
        'entity.type' => 'SERVICE',
        'entity.guid' => 'EntityGUID',
        'hostname' => 'HostName',
        'trace.id' => trace_id,
        'span.id' => span_id
      }
      assert_equal expected, linking_metadata
    end

    def test_linking_metadata_no_transaction
      setup_linking_metadata_stubs 'AppName', 'HostName', 'EntityGuid'

      expected = {
        'entity.name' => 'AppName',
        'entity.type' => 'SERVICE',
        'entity.guid' => 'EntityGuid',
        'hostname' => 'HostName'
      }
      assert_equal expected, NewRelic::Agent.linking_metadata
    end

    # It's not uncommon for customers to conclude a rescue block with a call to
    # notice_error.  We should always return nil, which mean less folks
    # unexpectedly get a noticed error Hash returned from their methods.
    def test_notice_error_returns_nil
      begin
        raise "WTF"
      rescue => e
        assert_nil ::NewRelic::Agent.notice_error(e)
      end
    end

    def test_disable_transaction_tracing_deprecated
      log = with_array_logger(:warn) do
        NewRelic::Agent.disable_transaction_tracing do
          in_transaction do |txn|
            # no-op
          end
        end
      end

      assert log.array.any? { |msg| msg.include?('The method disable_transaction_tracing is deprecated.') }
      assert log.array.any? { |msg| msg.include?('Please use disable_all_tracing or ignore_transaction instead.') }
    end

    def test_eventing_helpers
      called = false
      NewRelic::Agent.subscribe(:boo) { called = true }
      NewRelic::Agent.notify(:boo)
      assert called
    end

    def test_ignore_transaction_works
      in_transaction do |txn|
        NewRelic::Agent.ignore_transaction
        assert txn.ignore?
      end

      assert_empty NewRelic::Agent.instance.transaction_sampler.harvest!
    end

    # The assumption is that txn.ignore_apdex! works as expected, and is tested elsewhere.
    def test_ignore_apdex_works
      in_transaction do |txn|
        NewRelic::Agent.ignore_apdex
        assert txn.ignore_apdex?
      end
    end

    # The assumption is that txn.ignore_enduser! works as expected, and is tested elsewhere.
    def test_ignore_enduser_works
      in_transaction do |txn|
        NewRelic::Agent.ignore_enduser
        assert txn.ignore_enduser?
      end
    end

    DEPRECATED_CONSTANTS = [:Tms, :Passwd, :Group]

    def test_modules_and_classes_return_name_properly
      valid = [Module, Class]
      stack = [NewRelic]
      visited = []

      loop do
        visited << a = stack.pop
        if a.respond_to? :name
          assert_equal a, Kernel.const_get(a.name)
        end

        if a.respond_to? :constants
          consts = (a.constants - DEPRECATED_CONSTANTS).map { |c| a.const_get c }.select do |c|
            if valid.include?(c.class) && !c.ancestors.include?(Minitest::Test)
              assert_instance_of String, c.name
              c.name.start_with?(a.name)
            else
              false
            end
          end
          stack.concat (consts - visited)
        end

        break if stack.empty?
      end
    end

    private

    def with_unstarted_agent
      old_agent = NewRelic::Agent.agent
      NewRelic::Agent.instance_eval { @agent = nil }
      yield
    ensure
      NewRelic::Agent.instance_eval { @agent = old_agent }
    end

    def mocked_agent
      agent = mock('agent')
      NewRelic::Agent.stubs(:agent).returns(agent)
      agent
    end

    def mocked_control
      server = NewRelic::Control::Server.new('localhost', 3000)
      control = OpenStruct.new(:license_key => 'abcdef',
        :server => server)
      control.instance_eval do
        def [](key)
          nil
        end

        def fetch(k, d)
          nil
        end
      end

      NewRelic::Control.stubs(:instance).returns(control)
      control
    end
  end
end
