# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'rack/test'
require 'new_relic/rack/agent_hooks'
require './testing_app'

class SyntheticsTest < Minitest::Test
  include MultiverseHelpers
  include Rack::Test::Methods

  setup_and_teardown_agent

  def app
    Rack::Builder.app { run TestingApp.new }
  end

  def last_sent_analytics_event
    calls = $collector.calls_for(:analytic_event_data)
    assert_equal(1, calls.size)
    events = calls.first.events
    assert_equal(1, events.size)
    events.first
  end

  def last_sent_transaction_trace
    calls = $collector.calls_for(:transaction_sample_data)
    assert_equal(1, calls.size)
    traces = calls.first.samples
    assert_equal(1, traces.size)
    traces.first
  end

  def generate_synthetics_header(test)
    synthetics_key     = test['settings']['syntheticsEncodingKey']
    synthetics_payload = test['inputHeaderPayload']

    return nil if synthetics_payload.empty?

    encoded_synthetics_payload   = ::NewRelic::JSONWrapper.dump(synthetics_payload)
    obfuscated_synthetics_header = ::NewRelic::Agent::Obfuscator.new(synthetics_key).obfuscate(encoded_synthetics_payload)

    assert_equal(test['inputObfuscatedHeader']['X-NewRelic-Synthetics'], obfuscated_synthetics_header)
    obfuscated_synthetics_header
  end

  def request_headers_for_test(test)
    header_value = generate_synthetics_header(test)
    if header_value
      { 'HTTP_X_NEWRELIC_SYNTHETICS' => header_value }
    else
      {}
    end
  end

  def request_params_for_test(test)
    if test['settings']
      { 'guid' => test['settings']['transactionGuid'] }
    else
      {}
    end
  end

  def validate_transaction_event(event, test)
    event_spec               = test['outputTransactionEvent']
    expected_event_attrs     = event_spec['expectedAttributes']
    non_expected_event_attrs = event_spec['nonExpectedAttributes']

    expected_event_attrs.each do |key, value|
      msg = "Incorrect value for analytic event key '#{key}'. Full event = #{event.inspect}"
      assert_equal(value, event[0][key], msg) unless key == 'nr.guid' && event[0][key] == nil
    end

    non_expected_event_attrs.each do |key|
      msg = "Did not expect key '#{key}' on analytics event. Actual value was #{event[0][key]}"
      refute_includes(event[0].keys, key, msg)
    end
  end

  def validate_transaction_trace(trace, test)
    trace_spec           = test['outputTransactionTrace']
    expected_resource_id = trace_spec['header']['field_9']
    expected_attrs       = trace_spec['expectedIntrinsics']
    non_expected_attrs   = trace_spec['nonExpectedIntrinsics']

    trace_attrs          = trace.intrinsic_attributes

    assert_equal(expected_resource_id, trace.synthetics_resource_id)

    expected_attrs.each do |key, value|
      key = "#{key}"
      msg = "Incorrect value for transaction trace intrinsic '#{key}'. All intrinsics = #{trace_attrs.inspect}"
      assert_equal(value, trace_attrs[key], msg)
    end

    non_expected_attrs.each do |key|
      key = "#{key}"
      msg = "Did not expect key '#{key}' on transaction trace. Actual value was #{trace_attrs[key]}"
      refute_includes(trace_attrs.keys, key, msg)
    end
  end

  # These tests do *not* cover passing on the correct synthetics header to
  # outgoing HTTP requests, since testing that requires our various HTTP client
  # libraries to be present. That aspect is tested in http_client_test_cases.rb
  load_cross_agent_test('synthetics/synthetics').each do |test|
    define_method("test_synthetics_#{test['name']}") do
      config = {
        :encoding_key        => test['settings']['agentEncodingKey'],
        :trusted_account_ids => test['settings']['trustedAccountIds'],
        :'transaction_tracer.transaction_threshold' => 0.0
      }

      with_config(config) do
        NewRelic::Agent.instance.events.notify(:finished_configuring)

        get '/', request_params_for_test(test), request_headers_for_test(test)

        NewRelic::Agent.agent.send(:transmit_data)
        NewRelic::Agent.agent.send(:harvest_and_send_analytic_event_data)

        event = last_sent_analytics_event
        validate_transaction_event(event, test)

        trace = last_sent_transaction_trace
        validate_transaction_trace(trace, test)
      end
    end
  end
end
