# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# https://newrelic.atlassian.net/wiki/display/eng/The+Terror+and+Glory+of+Transaction+Traces
# https://newrelic.atlassian.net/browse/RUBY-914
require 'ostruct'

class MarshalingTest < Minitest::Test
  include MultiverseHelpers
  include NewRelic::Agent::MethodTracer

  setup_and_teardown_agent(:'transaction_tracer.transaction_threshold' => 0.0) do |collector|
    collector.stub('connect', {'agent_run_id' => 666})
  end

  def test_transaction_trace_marshaling
    nr_freeze_time

    in_transaction do
      trace_execution_scoped('a') do
        trace_execution_scoped('ab') do
          advance_time 1
        end
      end
    end

    expected_sample = last_transaction_trace

    agent.service.connect
    agent.send(:harvest_and_send_transaction_traces)

    actual = $collector.calls_for('transaction_sample_data')[0][1][0]
    encoder = NewRelic::Agent::NewRelicService::Encoders::Identity

    expected = expected_sample.to_collector_array(encoder)
    expected = NewRelic::Agent::EncodingNormalizer.normalize_object(expected)

    assert_equal(expected, actual)
  end

  def test_metric_data_marshalling
    metric = 'Custom/test/method'
    NewRelic::Agent.record_metric metric, 1.0
    NewRelic::Agent.record_metric metric, 2.0

    expected = [2, 3.0, 3.0, 1.0, 2.0, 5.0]

    agent.service.connect
    agent.send(:harvest_and_send_timeslice_data)

    assert_equal('666', $collector.calls_for('metric_data')[0].run_id)

    custom_metric = $collector.reported_stats_for_metric('Custom/test/method')[0]
    assert_equal(expected, custom_metric)
  end

  def test_error_data_marshalling
    agent.error_collector.notice_error(Exception.new('test error'))
    agent.service.connect
    agent.send(:harvest_and_send_errors)

    assert_equal('666', $collector.calls_for('error_data')[0].run_id)

    error_data = $collector.calls_for('error_data')[0][1][0]
    assert_equal('test error', error_data[2])
  end

  def test_sql_trace_data_marshalling
    in_transaction do
      agent.sql_sampler.notice_sql("select * from test", "Database/test/select",
        nil, 1.5)
    end

    agent.service.connect
    agent.send(:harvest_and_send_slowest_sql)

    sql_data = $collector.calls_for('sql_trace_data')[0][0]
    assert_equal('select * from test', sql_data[0][3])
  end

  def test_connect_marshalling
    agent.service.connect('pid' => 1, 'agent_version' => '9000',
      'app_name' => 'test')

    connect_data = $collector.calls_for('connect').last
    assert_equal '9000', connect_data['agent_version']
  end
end
