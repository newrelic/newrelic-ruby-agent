# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..', '..', '..','test_helper'))
require 'new_relic/agent/agent'
require 'ostruct'

class NewRelic::Agent::Agent::ConnectTest < Minitest::Test
  include NewRelic::Agent::Agent::Connect
  include TransactionSampleTestHelper

  def setup
    @connected = nil
    @keep_retrying = nil
    @connect_attempts = 0
    @connect_retry_period = 0
    events = NewRelic::Agent.instance.events
    @transaction_sampler = NewRelic::Agent::TransactionSampler.new
    @sql_sampler = NewRelic::Agent::SqlSampler.new
    @error_collector = NewRelic::Agent::ErrorCollector.new events
    @stats_engine = NewRelic::Agent::StatsEngine.new
    server = NewRelic::Control::Server.new('localhost', 30303)
    @service = NewRelic::Agent::NewRelicService.new('abcdef', server)
    NewRelic::Agent.instance.service = @service

    NewRelic::Agent.reset_config
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
    assert_equal  15, next_retry_period
    assert_equal  15, next_retry_period
    assert_equal  30, next_retry_period
    assert_equal  60, next_retry_period
    assert_equal 120, next_retry_period
    assert_equal 300, next_retry_period
    assert_equal 300, next_retry_period
    assert_equal 300, next_retry_period
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

  def test_configure_transaction_tracer_positive
    with_config(:'transaction_tracer.enabled' => true) do
      assert @transaction_sampler.enabled?
    end
  end

  def test_configure_transaction_tracer_negative
    with_config(:'transaction_tracer.enabled' => false) do
      refute @transaction_sampler.enabled?
    end
  end

  def test_configure_transaction_tracer_server_disabled
    config = NewRelic::Agent::Configuration::ServerSource.new('collect_traces' => false)
    with_config(config) do
      refute @transaction_sampler.enabled?
    end
  end

  def test_apdex_f
    with_config(:apdex_t => 10) do
      assert_equal 40, apdex_f
    end
  end

  def test_set_sql_recording_default
    with_config(:'transaction_tracer.record_sql' => 'obfuscated') do
      assert_equal(:obfuscated, NewRelic::Agent::Database.record_sql_method)
    end
  end

  def test_set_sql_recording_off
    with_config(:'transaction_tracer.record_sql' => 'off') do
      assert_equal(:off, NewRelic::Agent::Database.record_sql_method)
    end
  end

  def test_set_sql_recording_none
    with_config(:'transaction_tracer.record_sql' => 'none') do
      assert_equal(:off, NewRelic::Agent::Database.record_sql_method)
    end
  end

  def test_set_sql_recording_raw
    with_config(:'transaction_tracer.record_sql' => 'raw') do
      assert_equal(:raw, NewRelic::Agent::Database.record_sql_method)
    end
  end

  def test_set_sql_recording_falsy
    with_config(:'transaction_tracer.record_sql' => false) do
      assert_equal(:off, NewRelic::Agent::Database.record_sql_method)
    end
  end

  def test_connect_gets_config
    NewRelic::Agent.manual_start
    NewRelic::Agent.instance.service = default_service(
      :connect => {'agent_run_id' => 23, 'config' => 'a lot'})

    response = NewRelic::Agent.agent.connect_to_server

    assert_equal 23, response['agent_run_id']
    assert_equal 'a lot', response['config']

    NewRelic::Agent.shutdown
  end

  def test_connect_memoizes_event_harvest_config
    default_source = NewRelic::Agent::Configuration::DefaultSource.new
    expected_event_harvest_config_payload = {
      :harvest_limits => {
        :analytic_event_data => default_source[:'analytics_events.max_samples_stored'],
        :custom_event_data => default_source[:'custom_insights_events.max_samples_stored'],
        :error_event_data => default_source[:'error_collector.max_event_samples_stored'],
        :span_event_data => default_source[:'span_events.max_samples_stored']
      }
    }

    NewRelic::Agent.instance.service.stubs(:connect)\
      # the stub connect service will return this canned response
      .returns({
        'agent_run_id' => 23,
        'event_harvest_config' => {
          'report_period_ms' => 5000,
          'harvest_limits' => { 'analytic_event_data'=>833, 'custom_event_data'=>83, 'error_event_data'=>8 }
        }
      })\
      # every call to :connect should pass the same expected event_harvest_config payload
      .with { |value| value[:event_harvest_config] == expected_event_harvest_config_payload }

    # Calling connect twice should send the same event data both times
    NewRelic::Agent.agent.connect_to_server
    NewRelic::Agent.agent.connect_to_server
  end

  def test_logging_collector_messages
    NewRelic::Agent.manual_start
    NewRelic::Agent.instance.service = default_service(
      :connect => {
        'messages' => [{ 'message' => 'beep boop', 'level' => 'INFO' },
                       { 'message' => 'ha cha cha', 'level' => 'WARN' }]
      })

    expects_logging(:info, 'beep boop')
    expects_logging(:warn, 'ha cha cha')

    NewRelic::Agent.agent.connect_to_server
    NewRelic::Agent.shutdown
  end

  def test_environment_for_connect
    assert environment_for_connect.detect{ |(k, _)|
      k == 'Gems'
    }, "expected connect_settings to include gems from environment"
  end

  def test_environment_for_connect_negative
    with_config(:send_environment_info => false) do
      assert_equal [], environment_for_connect
    end
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

  def next_retry_period
    result = connect_retry_period
    note_connect_failure
    result
  end
end
