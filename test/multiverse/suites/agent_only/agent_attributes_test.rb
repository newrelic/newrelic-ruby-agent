# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class AgentAttributesTest < Minitest::Test

  include MultiverseHelpers

  setup_and_teardown_agent

  def test_http_response_code_default_destinations
    run_transaction do |txn|
      txn.http_response_code = 418
    end

    assert_transaction_trace_has_agent_attribute("httpResponseCode", 418)
    assert_event_has_agent_attribute("httpResponseCode", 418)
    assert_error_has_agent_attribute("httpResponseCode", 418)

    refute_browser_monitoring_has_agent_attribute("httpResponseCode")
  end

  def test_request_headers_referer_default_destinations
    txn_options = {:request => stub(:referer => "referrer", :path => "/")}
    run_transaction({}, txn_options) do |txn|
    end

    assert_error_has_agent_attribute("request.headers.referer", "referrer")

    refute_transaction_trace_has_agent_attribute("request.headers.referer")
    refute_event_has_agent_attribute("request.headers.referer")
    refute_browser_monitoring_has_agent_attribute("request.headers.referer")
  end

  def test_request_parameters_default_destinations_without_capture_params
    run_transaction(:capture_params => false) do |txn|
      txn.merge_request_parameters(:duly => "noted")
    end

    refute_transaction_trace_has_agent_attribute("request.parameters.duly")
    refute_event_has_agent_attribute("request.parameters.duly")
    refute_error_has_agent_attribute("request.parameters.duly")
    refute_browser_monitoring_has_agent_attribute("request.parameters.duly")
  end

  def test_request_parameters_default_destinations_with_capture_params
    run_transaction(:capture_params => true) do |txn|
      txn.merge_request_parameters(:duly => "noted")
    end

    assert_transaction_trace_has_agent_attribute("request.parameters.duly", "noted")
    assert_error_has_agent_attribute("request.parameters.duly", "noted")

    refute_event_has_agent_attribute("request.parameters.duly")
    refute_browser_monitoring_has_agent_attribute("request.parameters.duly")
  end

  def test_custom_attributes_included
    run_transaction do
      NewRelic::Agent.add_custom_attributes(:foo => 'bar')
    end

    assert_transaction_tracer_has_custom_attributes('foo', 'bar')
    assert_transaction_event_has_custom_attributes('foo', 'bar')
    assert_error_collector_has_custom_attributes('foo', 'bar')
    assert_browser_monitoring_has_custom_attributes('foo', 'bar')
  end

  def test_custom_attributes_excluded
    config = {
      :'transaction_tracer.attributes.enabled' => false,
      :'transaction_events.attributes.enabled' => false,
      :'error_collector.attributes.enabled'    => false,
      :'browser_monitoring.attributes.enabled' => false
    }

    run_transaction(config) do
      NewRelic::Agent.add_custom_attributes(:foo => 'bar')
    end

    refute_transaction_tracer_has_custom_attributes('foo')
    refute_transaction_event_has_custom_attributes('foo')
    refute_error_collector_has_custom_attributes('foo')
    refute_browser_monitoring_has_custom_attributes('foo')
  end

  def test_custom_attributes_excluded_with_global_config
    run_transaction(:'attributes.enabled' => false) do
      NewRelic::Agent.add_custom_attributes(:foo => 'bar')
    end

    refute_transaction_tracer_has_custom_attributes('foo')
    refute_transaction_event_has_custom_attributes('foo')
    refute_error_collector_has_custom_attributes('foo')
    refute_browser_monitoring_has_custom_attributes('foo')
  end

  def test_request_parameters_captured_on_transaction_events_when_enabled
    config = {:'transaction_events.attributes.include' => 'request.parameters.*'}
    txn_options = {
      :filtered_params => {:foo => "bar", :bar => "baz"}
    }
    run_transaction(config, txn_options)

    assert_event_has_agent_attribute("request.parameters.foo", "bar")
    assert_event_has_agent_attribute("request.parameters.bar", "baz")
  end

  def test_request_parameters_captured_in_bam_when_enabled
    config = {:'browser_monitoring.attributes.include' => 'request.parameters.*'}
    txn_options = {
      :filtered_params => {:foo => "bar", :bar => "baz"}
    }
    run_transaction(config, txn_options)

    assert_browser_monitoring_has_agent_attribute("request.parameters.foo", "bar")
    assert_browser_monitoring_has_agent_attribute("request.parameters.bar", "baz")
  end

  def run_transaction(config = {}, txn_options = {})
    default_config = {
      :'transaction_tracer.transaction_threshold' => -10,
      :'transaction_tracer.attributes.enabled' => true,
      :'transaction_events.attributes.enabled' => true,
      :'error_collector.attributes.enabled'    => true,
      :'browser_monitoring.attributes.enabled' => true
    }

    assert_raises(RuntimeError) do
      with_config(default_config.merge(config)) do
        in_transaction(txn_options) do |txn|
          yield(txn) if block_given?

          # JS instrumentation happens within transaction, so capture it now
          capture_js_data

          # Have to raise an error to exercise attribute capture there
          raise "O_o"
        end
      end
    end

    run_harvest
  end
end
