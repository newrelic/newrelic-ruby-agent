# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

class LogEventsTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  def test_log_event_data_sent_in_transaction
    trace_id = nil
    span_id = nil
    with_config(:'application_logging.forwarding.enabled' => true) do
      in_transaction do |txn|
        NewRelic::Agent.agent.log_event_aggregator.reset!
        NewRelic::Agent.agent.log_event_aggregator.record("Deadly", "FATAL")
        trace_id = NewRelic::Agent::Tracer.current_trace_id
        span_id = NewRelic::Agent::Tracer.current_span_id
      end

      NewRelic::Agent.agent.send(:harvest_and_send_log_event_data)
    end

    last_log = last_log_event
    assert_equal "Deadly", last_log["message"]
    assert_equal "FATAL", last_log["level"]
    assert_equal trace_id, last_log["trace.id"]
    assert_equal span_id, last_log["span.id"]

    common = last_logs_common
    assert_equal nil, common["attributes"]["entity.type"]
    assert_equal NewRelic::Agent::Hostname.get, common["attributes"]["hostname"]
  end

  def test_log_event_data_sent_no_transaction
    NewRelic::Agent.agent.log_event_aggregator.reset!
    with_config(:'application_logging.forwarding.enabled' => true) do
      NewRelic::Agent.agent.log_event_aggregator.record("Deadly", "FATAL")
      NewRelic::Agent.agent.send(:harvest_and_send_log_event_data)
    end

    last_log = last_log_event
    assert_equal "Deadly", last_log["message"]
    assert_equal "FATAL", last_log["level"]
    assert_equal nil, last_log["trace.id"]
    assert_equal nil, last_log["span.id"]

    common = last_logs_common
    assert_equal nil, common["attributes"]["entity.type"]
    assert_equal NewRelic::Agent::Hostname.get, common["attributes"]["hostname"]
  end

  def last_log_event
    post = last_log_post
    assert_equal(1, post.logs.size)
    post.logs.last
  end

  def last_logs_common
    post = last_log_post
    post.common
  end

  def last_log_post
    $collector.calls_for(:log_event_data).first
  end
end
