# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

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
    t0 = freeze_time(Time.at(Time.now.to_i))

    with_around_hook do
      Transactioner.new.do_it
    end

    transmit_event_data

    result = $collector.calls_for('analytic_event_data')
    assert_equal 1, result.length
    events = result.first.events
    assert_equal 1, events.length

    expected_event = [
      {
        "type"      => "Transaction",
        "timestamp" => t0.to_f,
        "name"      => "TestTransaction/do_it",
        "duration"  => 0.0,
        "error"     => false
      },
      {},
      {}
    ]

    event = events.first
    # this is only present on REE, and we don't really care - the point of this
    # test is just to validate basic marshalling
    event[0].delete("gcCumulative")

    assert_equal(expected_event, event)
  end

  def test_sends_custom_events
    t0 = freeze_time

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
        "type"      => "CustomEventType",
        "timestamp" => t0.to_i
      },
      {
        "foo" => "bar",
        "baz" => "qux"
      }
    ]

    assert_equal(expected_event, events.first)
  end

  def test_sends_error_events
    t0 = freeze_time(Time.at(Time.now.to_i))

    with_around_hook do
      Transactioner.new.break_it
    end

    transmit_data

    result = $collector.calls_for('error_event_data')

    assert_equal 1, result.length
    events = result.first.events
    assert_equal 1, events.length

    expected_event = [
      {
        "type" => "TransactionError",
        "error.class" => "StandardError",
        "error.message" => "Sorry!",
        "timestamp" => t0.to_f,
        "transactionName" => "TestTransaction/break_it",
        "duration" => 0.0
      },
      {},
      {}
    ]

    event = events.first
    # this is only present on REE, and we don't really care - the point of this
    # test is just to validate basic marshalling
    event[0].delete("gcCumulative")
    assert_equal(expected_event, event)
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
    NewRelic::Agent.instance.send(:transmit_event_data)
  end
end
