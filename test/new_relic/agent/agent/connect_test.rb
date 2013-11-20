# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..', '..', '..','test_helper'))
require 'new_relic/agent/agent'
require 'ostruct'

class NewRelic::Agent::Agent::ConnectTest < Test::Unit::TestCase
  include NewRelic::Agent::Agent::Connect
  include TransactionSampleTestHelper

  def setup
    @connected = nil
    @keep_retrying = nil
    @connect_attempts = 0
    @connect_retry_period = 0
    @transaction_sampler = NewRelic::Agent::TransactionSampler.new
    @sql_sampler = NewRelic::Agent::SqlSampler.new
    @error_collector = NewRelic::Agent::ErrorCollector.new
    @stats_engine = NewRelic::Agent::StatsEngine.new
    server = NewRelic::Control::Server.new('localhost', 30303)
    @service = NewRelic::Agent::NewRelicService.new('abcdef', server)
    @test_config = { :developer_mode => true }
    NewRelic::Agent.config.apply_config(@test_config)
  end

  def teardown
    NewRelic::Agent.config.remove_config(@test_config)
  end

  def control
    fake_control = OpenStruct.new('local_env' => OpenStruct.new('snapshot' => []))
    fake_control.instance_eval do
      def [](key)
        return nil
      end
    end
    fake_control
  end

  def test_should_connect_if_pending
    @connect_state = :pending
    assert(should_connect?, "should attempt to connect if pending")
  end

  def test_should_not_connect_if_disconnected
    @connect_state = :disconnected
    assert(!should_connect?, "should not attempt to connect if force disconnected")
  end

  def test_should_connect_if_forced
    @connect_state = :disconnected
    assert(should_connect?(true), "should connect if forced")
    @connect_state = :connected
    assert(should_connect?(true), "should connect if forced")
  end

  def test_increment_retry_period
    10.times do |i|
      assert_equal((i * 60), connect_retry_period)
      note_connect_failure
    end
    assert_equal(600, connect_retry_period)
  end

  def test_disconnect
    assert disconnect
  end

  def test_log_error
    error = StandardError.new("message")

    expects_logging(:error,
      includes("Error establishing connection with New Relic Service"), \
      instance_of(StandardError))

    log_error(error)
  end

  def test_handle_license_error
    error = mock(:message => "error message")
    self.expects(:disconnect).once
    handle_license_error(error)
  end

  def test_connect_settings_have_environment_report
    NewRelic::Agent.agent.generate_environment_report
    assert NewRelic::Agent.agent.connect_settings[:environment].detect{ |(k, _)|
      k == 'Gems'
    }, "expected connect_settings to include gems from environment"
  end

  def test_environment_for_connect_negative
    with_config(:send_environment_info => false) do
      NewRelic::Agent.agent.generate_environment_report
      assert_equal [], NewRelic::Agent.agent.connect_settings[:environment]
    end
  end

  def test_connect_settings
    NewRelic::Agent.config.expects(:app_names)
    keys = %w(pid host app_name language agent_version environment settings)
    value = connect_settings
    keys.each do |k|
      assert(value.has_key?(k.to_sym), "should include the key #{k}")
    end
  end

  def test_configure_transaction_tracer_positive
    with_config(:'transaction_tracer.enabled' => true) do
      assert @transaction_sampler.enabled?
    end
  end

  def test_configure_transaction_tracer_negative
    with_config(:'transaction_tracer.enabled' => false) do
      assert @transaction_sampler.enabled?
    end
  end

  def test_configure_transaction_tracer_server_disabled
    config = NewRelic::Agent::Configuration::ServerSource.new('collect_traces' => false,
                                                              'developer_mode' => false)
    with_config(config) do
      assert !@transaction_sampler.enabled?
    end
  end

  def test_apdex_f
    with_config(:apdex_t => 10) do
      assert_equal 40, apdex_f
    end
  end

  def test_set_sql_recording_default
    with_config(:'transaction_tracer.record_sql' => 'obfuscated') do
      assert_equal(:obfuscated, NewRelic::Agent::Database.record_sql_method,
                   "should default to :obfuscated, was #{NewRelic::Agent::Database.record_sql_method}")
    end
  end

  def test_set_sql_recording_off
    with_config(:'transaction_tracer.record_sql' => 'off') do
      assert_equal(:off, NewRelic::Agent::Database.record_sql_method,
                   "should be set to :off, was #{NewRelic::Agent::Database.record_sql_method}")
    end
  end

  def test_set_sql_recording_none
    with_config(:'transaction_tracer.record_sql' => 'none') do
      assert_equal(:off, NewRelic::Agent::Database.record_sql_method,
                   "should be set to :off, was #{NewRelic::Agent::Database.record_sql_method}")
    end
  end

  def test_set_sql_recording_raw
    with_config(:'transaction_tracer.record_sql' => 'raw') do
      assert_equal(:raw, NewRelic::Agent::Database.record_sql_method,
                   "should be set to :raw, was #{NewRelic::Agent::Database.record_sql_method}")
    end
  end

  def test_set_sql_recording_falsy
    with_config(:'transaction_tracer.record_sql' => false) do
      assert_equal(:off, NewRelic::Agent::Database.record_sql_method,
                   "should be set to :off, was #{NewRelic::Agent::Database.record_sql_method}")
    end
  end

  def test_query_server_for_configuration
    self.expects(:connect_to_server).returns("so happy")
    self.expects(:finish_setup).with("so happy")
    query_server_for_configuration
  end

  def test_connect_gets_config
    NewRelic::Agent.manual_start
    NewRelic::Agent::Agent.instance.service = default_service(
      :connect => {'agent_run_id' => 23, 'config' => 'a lot'})

    response = NewRelic::Agent.agent.connect_to_server

    assert_equal 23, response['agent_run_id']
    assert_equal 'a lot', response['config']

    NewRelic::Agent.shutdown
  end

  def test_finish_setup_saves_transaction_name_rules
    NewRelic::Agent.instance.instance_variable_set(:@transaction_rules,
                                            NewRelic::Agent::RulesEngine.new)
    config = {
      'transaction_name_rules' => [ { 'match_expression' => '88',
                                      'replacement'      => '**' },
                                    { 'match_expression' => 'xx',
                                      'replacement'      => 'XX' } ]
    }
    NewRelic::Agent.instance.finish_setup(config)

    rules = NewRelic::Agent.instance.transaction_rules
    assert_equal 2, rules.size
    assert(rules.find{|r| r.match_expression == /88/ && r.replacement == '**' },
           "rule not found among #{rules}")
    assert(rules.find{|r| r.match_expression == /xx/ && r.replacement == 'XX' },
           "rule not found among #{rules}")
  ensure
    NewRelic::Agent.instance.instance_variable_set(:@transaction_rules,
                                            NewRelic::Agent::RulesEngine.new)
  end

  def test_finish_setup_saves_metric_name_rules
    NewRelic::Agent.instance.instance_variable_set(:@metric_rules,
                                            NewRelic::Agent::RulesEngine.new)
    config = {
      'metric_name_rules' => [ { 'match_expression' => '77',
                                 'replacement'      => '&&' },
                               { 'match_expression' => 'yy',
                                 'replacement'      => 'YY' }]
    }
    finish_setup(config)

    rules = @stats_engine.metric_rules
    assert_equal 2, rules.size
    assert(rules.find{|r| r.match_expression == /77/ && r.replacement == '&&' },
           "rule not found among #{rules}")
    assert(rules.find{|r| r.match_expression == /yy/ && r.replacement == 'YY' },
           "rule not found among #{rules}")
  ensure
    NewRelic::Agent.instance.instance_variable_set(:@metric_rules,
                                            NewRelic::Agent::RulesEngine.new)
  end

  def test_finish_setup
    config = {
      'agent_run_id' => 'fishsticks',
      'collect_traces' => true,
      'collect_errors' => true,
      'sample_rate' => 10,
      'agent_config' => { 'transaction_tracer.record_sql' => 'raw' }
    }
    self.expects(:log_connection!).with(config)
    @transaction_sampler = stub('transaction sampler', :configure! => true,
                                :config => {})
    @sql_sampler = stub('sql sampler', :configure! => true)
    with_config(:'transaction_tracer.enabled' => true) do
      finish_setup(config)
      assert_equal 'fishsticks', @service.agent_id
      assert_equal 'raw', NewRelic::Agent.config[:'transaction_tracer.record_sql']
    end
  end


  def test_logging_collector_messages
    NewRelic::Agent.manual_start
    NewRelic::Agent::Agent.instance.service = default_service(
      :connect => {
        'messages' => [{ 'message' => 'beep boop', 'level' => 'INFO' },
                       { 'message' => 'ha cha cha', 'level' => 'WARN' }]
      })

    expects_logging(:info, 'beep boop')
    expects_logging(:warn, 'ha cha cha')

    NewRelic::Agent.agent.query_server_for_configuration
    NewRelic::Agent.shutdown
  end

  def test_finish_setup_without_config
    @service.agent_id = 'blah'
    finish_setup(nil)
    assert_equal 'blah', @service.agent_id
  end

  private

  def mocked_control
    fake_control = mock('control')
    self.stubs(:control).returns(fake_control)
    fake_control
  end

  def mocked_error_collector
    fake_collector = mock('error collector')
    self.stubs(:error_collector).returns(fake_collector)
    fake_collector
  end
end
