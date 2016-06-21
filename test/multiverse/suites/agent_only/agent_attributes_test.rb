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

    assert_transaction_trace_has_agent_attribute("httpResponseCode", "418")
    assert_event_has_agent_attribute("httpResponseCode", "418")
    assert_error_has_agent_attribute("httpResponseCode", "418")

    refute_browser_monitoring_has_agent_attribute("httpResponseCode")
  end

  def test_response_content_type_default_destinations
    run_transaction do |txn|
      txn.response_content_type = 'application/json'
    end

    assert_transaction_trace_has_agent_attribute("response.headers.contentType", "application/json")
    assert_event_has_agent_attribute("response.headers.contentType", "application/json")
    assert_error_has_agent_attribute("response.headers.contentType", "application/json")

    refute_browser_monitoring_has_agent_attribute("response.headers.contentType")
  end

  def test_response_content_length_default_destinations
    run_transaction do |txn|
      txn.response_content_length = 100
    end

    assert_transaction_trace_has_agent_attribute("response.headers.contentLength", 100)
    assert_event_has_agent_attribute("response.headers.contentLength", 100)
    assert_error_has_agent_attribute("response.headers.contentLength", 100)

    refute_browser_monitoring_has_agent_attribute("response.headers.contentLength")
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

  def test_agent_attributes_assigned_from_request
    request = stub(
      :path => "/",
      :referer => "http://docs.newrelic.com",
      :env => {"HTTP_ACCEPT" => "application/json"},
      :content_length => 103,
      :content_type => "application/json",
      :host => 'chippy',
      :user_agent => 'Use This!',
      :request_method => "GET"
    )

    run_transaction({}, {:request => request}) do |txn|
    end

    assert_error_has_agent_attribute "request.headers.referer", "http://docs.newrelic.com"
    refute_transaction_trace_has_agent_attribute "request.headers.referer"
    refute_event_has_agent_attribute "request.headers.referer"
    refute_browser_monitoring_has_agent_attribute "request.headers.referer"

    assert_transaction_trace_has_agent_attribute "request.headers.accept", "application/json"
    assert_event_has_agent_attribute "request.headers.accept", "application/json"
    assert_error_has_agent_attribute "request.headers.accept", "application/json"
    refute_browser_monitoring_has_agent_attribute "request.headers.accept"

    assert_transaction_trace_has_agent_attribute "request.headers.contentLength", 103
    assert_event_has_agent_attribute "request.headers.contentLength", 103
    assert_error_has_agent_attribute "request.headers.contentLength", 103
    refute_browser_monitoring_has_agent_attribute "request.headers.contentLength"

    assert_transaction_trace_has_agent_attribute "request.headers.contentType", "application/json"
    assert_event_has_agent_attribute "request.headers.contentType", "application/json"
    assert_error_has_agent_attribute "request.headers.contentType", "application/json"
    refute_browser_monitoring_has_agent_attribute "request.headers.contentType"

    assert_transaction_trace_has_agent_attribute "request.headers.host", "chippy"
    assert_event_has_agent_attribute "request.headers.host", "chippy"
    assert_error_has_agent_attribute "request.headers.host", "chippy"
    refute_browser_monitoring_has_agent_attribute "request.headers.host"

    assert_transaction_trace_has_agent_attribute "request.headers.userAgent", "Use This!"
    assert_event_has_agent_attribute "request.headers.userAgent", "Use This!"
    assert_error_has_agent_attribute "request.headers.userAgent", "Use This!"
    refute_browser_monitoring_has_agent_attribute "request.headers.userAgent"

    assert_transaction_trace_has_agent_attribute "request.method", "GET"
    assert_event_has_agent_attribute "request.method", "GET"
    assert_error_has_agent_attribute "request.method", "GET"
    refute_browser_monitoring_has_agent_attribute "request.method"
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

  def test_nils_excluded
    run_transaction do
      NewRelic::Agent.add_custom_attributes(:foo => nil)
    end

    refute_transaction_tracer_has_custom_attributes('foo')
    refute_transaction_event_has_custom_attributes('foo')
    refute_error_collector_has_custom_attributes('foo')
    refute_browser_monitoring_has_custom_attributes('foo')
  end

  def test_falses_included
    run_transaction do
      NewRelic::Agent.add_custom_attributes(:foo => false)
    end

    assert_transaction_tracer_has_custom_attributes('foo', false)
    assert_transaction_event_has_custom_attributes('foo', false)
    assert_error_collector_has_custom_attributes('foo', false)
    assert_browser_monitoring_has_custom_attributes('foo', false)
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

  def test_request_uri_captured_on_transaction_events_when_enabled
    config = {:'transaction_events.attributes.include' => 'request_uri'}
    txn_options = {
      :request => stub(:path => "/foobar")
    }
    run_transaction(config, txn_options)

    assert_event_has_agent_attribute("request_uri", "/foobar")
    refute_error_has_agent_attribute("request_uri")
    refute_transaction_trace_has_agent_attribute("request_uri")
    refute_browser_monitoring_has_agent_attribute("request_uri")
  end

  def test_request_uri_excluded_by_default
    config = {:'transaction_events.attributes.include' => ''}
    txn_options = {
      :request => stub(:path => "/foobar")
    }
    run_transaction(config, txn_options)

    refute_event_has_agent_attribute("request_uri")
    refute_error_has_agent_attribute("request_uri")
    refute_transaction_trace_has_agent_attribute("request_uri")
    refute_browser_monitoring_has_agent_attribute("request_uri")
  end

  def test_request_uri_not_captured_on_transaction_traces
    config = {:'transaction_tracer.attributes.include' => 'request_uri'}
    txn_options = {
      :request => stub(:path => "/foobar")
    }
    run_transaction(config, txn_options)

    refute_transaction_trace_has_agent_attribute("request_uri")
  end

  def test_request_uri_not_captured_on_error_traces
    config = {:'error_collector.attributes.include' => 'request_uri'}
    txn_options = {
      :request => stub(:path => "/foobar")
    }
    run_transaction(config, txn_options)
    
    refute_error_has_agent_attribute("request_uri")
  end

  def test_request_uri_not_captured_on_traces_if_only_configured_as_general_attribute
    config = {:'attributes.include' => 'request_uri'}
    txn_options = {
      :request => stub(:path => "/foobar")
    }
    run_transaction(config, txn_options)

    refute_transaction_trace_has_agent_attribute("request_uri")
    refute_error_has_agent_attribute("request_uri")
    refute_event_has_agent_attribute("request_uri")
  end

  def test_request_uri_only_included_on_transaction_events_with_attributes_include_wildcard
    config = { :'attributes.include' => '*',
               :'transaction_events.attributes.include' => 'request_uri'}

    txn_options = {
      :request => stub(:path => "/foobar")
    }
    run_transaction(config, txn_options)

    assert_event_has_agent_attribute("request_uri", "/foobar")
    refute_transaction_trace_has_agent_attribute("request_uri")
    refute_error_has_agent_attribute("request_uri")
  end

  def test_request_uri_captured_with_wildcard
    config = {:'transaction_events.attributes.include' => '*'}
    txn_options = {
      :request => stub(:path => "/foobar")
    }
    run_transaction(config, txn_options)

    assert_event_has_agent_attribute("request_uri", "/foobar")
  end

  def test_http_response_code_excluded_in_txn_events_when_disabled
    with_config(:'transaction_events.attributes.exclude' => 'httpResponseCode') do
      in_web_transaction do |txn|
        txn.http_response_code = 200
      end
    end

    run_harvest

    refute_event_has_attribute('httpResponseCode')
  end

  def test_host_display_name_included_when_enabled_and_set
    config = {:'process_host.display_name' => 'Fancy Host Name',
              :'transaction_events.attributes.include' => 'host.displayName',}
    run_transaction(config)

    assert_event_has_agent_attribute('host.displayName', 'Fancy Host Name')
  end

  def test_host_display_name_excluded_when_enabled_but_not_set
    config = {:'transaction_events.attributes.include' => 'host.displayName',}
    run_transaction(config)

    refute_event_has_attribute('host.displayName')
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
