# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'fake_server'

# These tests are designed to work in conjunction with a local newrelic.yml
# file set with "insecure" settings and the server returning "insecure" values,
# and confirm that high security changes the actual agent behavior, not just
# the settings in question.
class HighSecurityTest < Minitest::Test

  include MultiverseHelpers

  setup_and_teardown_agent do |collector|
    collector.use_ssl = true
    collector.stub('connect', {
      "agent_run_id" => 1,
      "agent_config" => {
        # Make sure that we take TT's all the time for testing purposes
        "transaction_tracer.transaction_threshold" => -10,

        # Really, really try to get us to allow things that we shouldn't when
        # in high security mode
        "capture_params" => true,

        "transaction_tracer.capture_attributes" => true,
        "error_collector.capture_attributes"    => true,
        "browser_monitoring.capture_attributes" => true,
        "analytics_events.capture_attributes"   => true,

        "attributes.enabled" => true,
        "attributes.include" => ["*", "request.parameters.*"],

        "transaction_tracer.attributes.enabled" => true,
        "transaction_tracer.attributes.include" => ["*", "request.parameters.*"],

        "transaction_events.attributes.enabled" => true,
        "transaction_events.attributes.include" => ["*", "request.parameters.*"],

        "error_collector.attributes.enabled" => true,
        "error_collector.attributes.include" => ["*", "request.parameters.*"],

        "browser_monitoring.attributes.enabled" => true,
        "browser_monitoring.attributes.include" => ["*", "request.parameters.*"],
      }
    }, 200)
  end

  def test_connects_via_ssl_no_matter_what
    assert_equal 1, $collector.calls_for('connect').size
    trigger_agent_reconnect(:ssl => false)
    assert_equal 2, $collector.calls_for('connect').size
  end

  def test_sends_high_security_flag_in_connect
    data = $collector.calls_for('connect')
    assert data.first.body["high_security"]
  end

  def test_disallows_server_config_from_overriding_high_security
    refute NewRelic::Agent.config[:capture_params]
  end

  def test_doesnt_capture_params_to_transaction_traces
    in_transaction(:filtered_params => { "loose" => "params" }) do
    end

    run_harvest

    trace = single_transaction_trace_posted
    assert_empty trace.custom_attributes
    assert_empty trace.agent_attributes
  end

  def test_doesnt_capture_params_to_errors
    assert_raises(RuntimeError) do
      in_transaction(:filtered_params => { "loose" => "params" }) do
        raise "O_o"
      end
    end

    run_harvest

    error = single_error_posted
    assert_empty error.agent_attributes
    assert_empty error.custom_attributes
  end

  def test_doesnt_capture_params_to_events
    in_transaction(:filtered_params => { "loose" => "params" }) do
    end

    run_harvest

    event = single_event_posted
    assert_empty event[1]
    assert_empty event[2]
  end

  def test_doesnt_capture_params_to_browser
    in_transaction(:filtered_params => { "loose" => "params" }) do
      capture_js_data
    end

    run_harvest

    refute_browser_monitoring_has_any_attributes
  end

  def test_disallows_custom_attributes_to_transaction_traces
    in_transaction do
      NewRelic::Agent.add_custom_attributes(:not => "allowed")
    end

    run_harvest

    trace = single_transaction_trace_posted
    assert_empty trace.custom_attributes
    assert_empty trace.agent_attributes
  end

  def test_disallows_custom_attributes_on_errors
    assert_raises(RuntimeError) do
      in_transaction do
        NewRelic::Agent.add_custom_attributes(:not => "allowed")
        raise "O_o"
      end
    end

    run_harvest

    error = single_error_posted
    assert_empty error.agent_attributes
    assert_empty error.custom_attributes
  end

  def test_disallows_custom_attributes_on_events
    in_transaction do
      NewRelic::Agent.add_custom_attributes(:not => "allowed")
    end

    run_harvest

    event = single_event_posted
    assert_empty event[1]
    assert_empty event[2]
  end

  def test_disallows_custom_attributes_on_browser
    in_transaction do
      NewRelic::Agent.add_custom_attributes(:not => "allowed")
      capture_js_data
    end

    run_harvest

    refute_browser_monitoring_has_any_attributes
  end

  def test_doesnt_block_agent_attributes_to_transaction_traces
    in_transaction do |txn|
      txn.http_response_code = 200
    end

    run_harvest

    expected = { "httpResponseCode" => "200" }
    assert_equal expected, single_transaction_trace_posted.agent_attributes
  end

  def test_doesnt_block_agent_attributes_to_errors
    assert_raises(RuntimeError) do
      in_transaction do |txn|
        txn.http_response_code = 500
        raise "O_o"
      end
    end

    run_harvest

    expected = { "httpResponseCode" => "500" }
    assert_equal expected, single_error_posted.agent_attributes
  end

  def test_doesnt_block_intrinsic_attributes_on_transaction_traces
    in_transaction do
      NewRelic::Agent::TransactionState.tl_get.is_cross_app_caller = true
    end

    run_harvest

    intrinsic_attributes = single_transaction_trace_posted.intrinsic_attributes
    refute_nil intrinsic_attributes['cpu_time']
    refute_nil intrinsic_attributes['trip_id']
    refute_nil intrinsic_attributes['path_hash']
  end

  def test_doesnt_block_intrinsic_attributes_on_errors
    assert_raises(RuntimeError) do
      in_transaction do
        NewRelic::Agent::TransactionState.tl_get.is_cross_app_caller = true
        raise "O_o"
      end
    end

    run_harvest

    intrinsic_attributes = single_error_posted.intrinsic_attributes
    refute_nil intrinsic_attributes['cpu_time']
    refute_nil intrinsic_attributes['trip_id']
    refute_nil intrinsic_attributes['path_hash']
  end
end
