# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

if RUBY_VERSION >= '1.9'

class EncodingHandlingTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  # We're hitting a Rubinius bug when running this test there:
  # https://github.com/rubinius/rubinius/issues/2899
  unless NewRelic::LanguageSupport.rubinius?
    def test_handles_mis_encoded_database_queries
      with_config(:'transaction_tracer.transaction_threshold' => 0.0,
        :'transaction_tracer.record_sql' => :raw) do
        in_transaction do
          state = NewRelic::Agent::TransactionState.tl_get
          agent.transaction_sampler.notice_sql(bad_string, nil, 42, state)
        end
        assert_endpoint_received_string('transaction_sample_data', normalized_bad_string)
      end
    end
  end

  def test_handles_mis_encoded_request_params
    with_config(:'capture_params' => true,
      :'transaction_tracer.transaction_threshold' => 0.0) do
      options = { :filtered_params => { bad_string => bad_string }}
      in_transaction(options) do
        # nothin
      end
    end
    assert_endpoint_received_string('transaction_sample_data', normalized_bad_string)
  end

  def test_handles_mis_encoded_custom_attributes
    with_config(:'transaction_tracer.transaction_threshold' => 0.0) do
      in_transaction do
        NewRelic::Agent.add_custom_attributes(:foo => bad_string)
      end
    end
    assert_endpoint_received_string('transaction_sample_data', normalized_bad_string)
  end

  def test_handles_mis_encoded_custom_attributes_on_analytics_events
    in_transaction(:category => :controller) do
      NewRelic::Agent.add_custom_attributes(:foo => bad_string)
    end
    assert_endpoint_received_string('analytic_event_data', normalized_bad_string)
  end

  def test_handles_mis_encoded_custom_attributes_on_errors
    NewRelic::Agent.notice_error('bad news', :custom_params => {'foo' => bad_string})
    assert_endpoint_received_string('error_data', normalized_bad_string)
  end

  def test_handles_mis_encoded_exception_message
    NewRelic::Agent.notice_error(bad_string)
    assert_endpoint_received_string('error_data', normalized_bad_string)
  end

  def test_handles_mis_encoded_metric_names
    NewRelic::Agent.record_metric(bad_string, 42)
    assert_endpoint_received_string('metric_data', normalized_bad_string)
  end

  def test_handles_mis_encoded_transaction_names
    with_config(:'transaction_tracer.transaction_threshold' => 0.0) do
      in_transaction do
        NewRelic::Agent.set_transaction_name(bad_string)
      end
    end
    expected_transaction_name = "other/#{normalized_bad_string}"
    assert_endpoint_received_string('transaction_sample_data', expected_transaction_name)
  end

  def test_handles_mis_encoded_strings_in_environment_report
    $collector.reset
    ::NewRelic::EnvironmentReport.report_on('Dummy') do
      bad_string
    end
    agent.instance_variable_set(:@environment_report, agent.environment_for_connect)
    agent.connect_to_server
    assert_endpoint_received_string('connect', normalized_bad_string)
  end

  def assert_endpoint_received_string(endpoint, string)
    agent.send(:transmit_data)
    agent.send(:transmit_event_data)
    requests = $collector.calls_for(endpoint)
    assert_equal(1, requests.size)
    request = requests.first
    request.decode! if request.respond_to?(:decode!)
    assert_contains_string(request, string)
  end

  def assert_contains_string(request, string)
    object_graph = request.body
    object_graph = request.samples if request.respond_to?(:samples)
    assert object_graph_contains_string?(request.body, string), "Did not find desired string in #{request.body.inspect}"
  end

  def object_graph_contains_string?(object_graph, string)
    case object_graph
    when String
      string == object_graph
    when Array
      object_graph.any? { |x| object_graph_contains_string?(x, string) }
    when Hash
      (
        object_graph_contains_string?(object_graph.keys, string) ||
        object_graph_contains_string?(object_graph.values, string)
      )
    else
      false
    end
  end

  def bad_string
    [128].to_a.pack("C*").force_encoding('UTF-8')
  end

  def normalized_bad_string
    bad_string.force_encoding('ISO-8859-1').encode('UTF-8')
  end
end

end
