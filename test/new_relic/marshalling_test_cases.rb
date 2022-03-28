# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

# These tests are intended to exercise the basic marshalling functionality of
# the agent in it's different permutations (Ruby and JSON)
module MarshallingTestCases
  def test_sends_metrics
    with_around_hook do
      NewRelic::Agent.record_metric('Boo', 42)
    end

    transmit_data

    result = $collector.calls_for('metric_data')
    assert_equal 1, result.length
    assert_includes result.first.metric_names, 'Boo'
  end

  def test_sends_errors
    with_around_hook do
      NewRelic::Agent.notice_error(StandardError.new("Boom"))
    end

    transmit_data

    result = $collector.calls_for('error_data')
    assert_equal 1, result.length
    assert_equal 1, result.first.errors.length
    assert_equal "StandardError", result.first.errors.first.exception_class_name
  end

  def test_sends_transaction_traces
    with_config(:'transaction_tracer.transaction_threshold' => -1.0) do
      with_around_hook do
        Transactioner.new.do_it
      end
    end

    transmit_data

    result = $collector.calls_for('transaction_sample_data')
    assert_equal 1, result.length
    assert_equal "TestTransaction/do_it", result.first.metric_name
  end

  def test_sends_transaction_events
    t0 = nr_freeze_process_time

    with_around_hook do
      Transactioner.new.do_it
    end

    transmit_event_data

    result = $collector.calls_for('analytic_event_data')
    assert_equal 1, result.length
    events = result.first.events
    assert_equal 1, events.length

    event = events.first
    # this is only present on REE, and we don't really care - the point of this
    # test is just to validate basic marshalling
    event[0].delete("gcCumulative")
    # this value will be randomly assigned and not useful to compare
    event[0].delete("priority")

    assert_equal "Transaction", event[0]["type"]
    assert_equal t0, event[0]["timestamp"]
    assert_equal "TestTransaction/do_it", event[0]["name"]
    assert_equal 0.0, event[0]["duration"]
    assert_equal false, event[0]["error"]
    assert_equal event[0]["parent.transportType"], "Unknown"
    assert event[0]['guid'] != nil
    assert event[0]["traceId"] != nil

    assert_equal 9, event[0].size
  end

  def test_sends_custom_events
    t0 = nr_freeze_process_time

    with_around_hook do
      NewRelic::Agent.record_custom_event("CustomEventType", :foo => 'bar', :baz => 'qux')
    end

    transmit_event_data

    result = $collector.calls_for('custom_event_data')
    assert_equal 1, result.length
    events = result.first.events
    assert_equal 1, events.length

    expected_event = [
      {
        "type" => "CustomEventType",
        "timestamp" => t0.to_i
      },
      {
        "foo" => "bar",
        "baz" => "qux"
      }
    ]

    # we don't care about the specific priority for this test
    events.first[0].delete("priority")

    assert_equal(expected_event, events.first)
  end

  def test_sends_error_events
    t0 = nr_freeze_process_time

    span_id = nil
    with_around_hook do
      span_id = Transactioner.new.break_it
    end

    transmit_data

    result = $collector.calls_for('error_event_data')

    assert_equal 1, result.length
    events = result.first.events
    assert_equal 1, events.length

    event = events.first

    # this is only present on REE, and we don't really care - the point of this
    # test is just to validate basic marshalling
    event[0].delete("gcCumulative")

    # we don't care about the specific priority for this test
    event[0].delete("priority")

    assert_equal "TransactionError", event[0]["type"]
    assert_equal "StandardError", event[0]["error.class"]
    assert_equal "Sorry!", event[0]["error.message"]
    assert_equal false, event[0]["error.expected"]
    assert_equal t0.to_f, event[0]["timestamp"]
    assert_equal "TestTransaction/break_it", event[0]["transactionName"]
    assert_equal 0.0, event[0]["duration"]
    assert_equal "Unknown", event[0]["parent.transportType"]
    assert event[0]["spanId"] != nil
    assert event[0]['guid'] != nil
    assert event[0]["traceId"] != nil

    assert_equal 12, event[0].size

    assert_equal event[1], {}
    assert_equal event[2], {}

    assert_equal event.size, 3
  end

  def test_sends_log_events
    # Standard with other agents on millis, not seconds
    t0 = nr_freeze_process_time.to_f * 1000
    message = "A deadly message"
    severity = "FATAL"

    with_config(:'application_logging.forwarding.enabled' => true) do
      with_around_hook do
        NewRelic::Agent.agent.log_event_aggregator.record(message, severity)
      end
    end

    transmit_data

    result = $collector.calls_for('log_event_data')
    assert_equal 1, result.length

    common = result.first.common["attributes"]
    refute_nil common["hostname"]

    # Excluding this explicitly vs classic logs-in-context to save space
    assert_nil common["entity.type"]

    logs = result.first.logs
    refute_empty logs

    log = logs.find { |l| l["message"] == message && l["level"] == severity }

    refute_nil log
    assert_equal t0, log["timestamp"]
  end

  class Transactioner
    include NewRelic::Agent::Instrumentation::ControllerInstrumentation

    def do_it
      NewRelic::Agent.set_transaction_name("do_it", :category => "TestTransaction")
    end

    add_transaction_tracer :do_it

    def break_it
      NewRelic::Agent.set_transaction_name("break_it", :category => "TestTransaction")
      NewRelic::Agent.notice_error StandardError.new("Sorry!")
      NewRelic::Agent::Tracer.current_span_id
    end

    add_transaction_tracer :break_it
  end

  def with_around_hook(&blk)
    if respond_to?(:around_each)
      around_each do
        blk.call
      end
    else
      blk.call
    end

    if respond_to?(:after_each)
      after_each
    end
  end

  def transmit_data
    NewRelic::Agent.instance.send(:transmit_data)
  end

  def transmit_event_data
    NewRelic::Agent.instance.send(:transmit_analytic_event_data)
    NewRelic::Agent.instance.send(:transmit_custom_event_data)
    NewRelic::Agent.instance.send(:transmit_error_event_data)
    NewRelic::Agent.instance.send(:transmit_span_event_data)
  end
end
