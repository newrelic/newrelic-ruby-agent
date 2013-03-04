# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# RUBY-980 Improve logging
# This test suite is for checking IMPORTANT conditions that we log rather than
# trying to do this via brittle unit tests

require 'logger'
require 'newrelic_rpm'
require 'fake_collector'
require 'mocha'

class LoggingTest < Test::Unit::TestCase

  def test_logs_app_name
    running_agent_writes_to_log( 
       {:app_name => "My App"},
       "Application: My App")
  end

  def test_logs_error_with_bad_app_name
    running_agent_writes_to_log( 
       {:app_name => false},
        "Unable to determine application name.")
  end

  def test_logs_dispatcher
    dispatcher = "Y U NO SERVER WEBPAGE"

    running_agent_writes_to_log(
      {:dispatcher => dispatcher},
      dispatcher)
  end

  def test_logs_missing_dispatcher
    running_agent_writes_to_log(
      {:dispatcher => ''},
      "No dispatcher detected")
  end

  def test_logs_raw_sql_warning
    running_agent_writes_to_log(
      {:'transaction_tracer.record_sql' => 'obfuscated'},
      "Agent is configured to send raw SQL to the service") do

      NewRelic::Agent.config.apply_config(:'transaction_tracer.record_sql' => 'raw')
    end

  end

  def test_logs_ssl_warning
    running_agent_writes_to_log(
      {:ssl => false},
      "Agent is configured not to use SSL when communicating with New Relic's servers") do

      NewRelic::Agent.config.apply_config(:ssl => false)
    end
  end

  def test_logs_ssl_verify_cert_warning
    running_agent_writes_to_log(
      {:ssl => false, :verify_certificate => false},
      "Agent is configured to use SSL but to skip certificate validation when communicating with New Relic's servers") do

      NewRelic::Agent.config.apply_config(:ssl => true, :verify_certificate => false)
    end
  end


  def test_logs_if_sending_errors_on_change
    running_agent_writes_to_log(
      {:'error_collector.enabled' => false},
      "Errors will be sent") do

      NewRelic::Agent.config.apply_config(:'error_collector.enabled' => true)
    end
  end

  def test_logs_if_not_sending_errors_on_change
    running_agent_writes_to_log(
      {:'error_collector.enabled' => true},
      "Errors will not be sent") do

      NewRelic::Agent.config.apply_config(:'error_collector.enabled' => false)
    end
  end

  def test_logs_transaction_tracing_disabled
    running_agent_writes_to_log(
      {:'transaction_tracer.enabled' => false},
      "Transaction traces will not be sent")
  end

  def test_invalid_license_key
    with_connect_response(401)
    running_agent_writes_to_log({},
      "Visit NewRelic.com to obtain a valid license key")
  end

  def test_logs_monitor_mode_disabled
    running_agent_writes_to_log(
      {:monitor_mode => false },
      "Agent configured not to send data in this environment.")
  end

  def test_logs_mising_license_key
    running_agent_writes_to_log(
      { :license_key => false },
      "No license key found in newrelic.yml config.")
  end

  def test_logs_invalid_license_key
    running_agent_writes_to_log(
      { :license_key => 'a' * 30 },
      "Invalid license key: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
  end

  def test_logs_forking_workers
    running_agent_writes_to_log(
      { :dispatcher => :passenger },
      "Connecting workers after forking.")
  end

  # Initialization
  def setup
    $collector ||= NewRelic::FakeCollector.new
    $collector.reset
    $collector.mock['connect'] = [200, {'return_value' => {"agent_run_id" => 666 }}]
    $collector.run

    NewRelic::Agent.reset_config 
    NewRelic::Agent::Agent.instance_variable_set(:@instance, nil)

    @logger = NewRelic::Agent::MemoryLogger.new
    NewRelic::Agent.logger = @logger
    NewRelic::Agent::AgentLogger.stubs(:new).with(any_parameters).returns(@logger)
  end

  def teardown
    $collector.reset

    # Really clear out our agent instance since we set bad license keys
    NewRelic::Agent::Agent.instance_variable_set(:@instance, nil)
  end

  # Helpers
  def running_agent_writes_to_log(options, msg)
    NewRelic::Agent.manual_start(options)
    yield if block_given?
    NewRelic::Agent.shutdown
    saw?(msg)
  end

  def with_connect_response(status=200, response={})
    $collector.mock['connect'] = [status, response]
  end

  def saw?(*expected_messages)
    flattened = @logger.messages.flatten
    expected_messages.each do |expected|
      found = flattened.any? {|msg| msg.to_s.include?(expected)}
      @logger.messages.each {|msg| puts msg.inspect} if !found
      assert(found, "Didn't see message '#{expected}'")
    end
  end
end
