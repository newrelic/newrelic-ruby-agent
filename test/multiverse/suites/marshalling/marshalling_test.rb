# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'multiverse_helpers'

# These tests are intended to exercise the basic marshalling functionality of
# the agent in it's different permutations (Ruby and JSON)
class MarshallingTest < Minitest::Test

  include MultiverseHelpers

  setup_and_teardown_agent

  def test_sends_metrics
    NewRelic::Agent.record_metric('Boo', 42)

    transmit_data

    result = $collector.calls_for('metric_data')
    assert_equal 1, result.length
    assert_includes result.first.metric_names, 'Boo'
  end

  def test_sends_errors
    NewRelic::Agent.notice_error(StandardError.new("Boom"))

    transmit_data

    result = $collector.calls_for('error_data')
    assert_equal 1, result.length
    assert_equal 1, result.first.errors.length
    assert_equal "StandardError", result.first.errors.first.exception_class_name
  end

  def test_sends_transaction_traces
    with_config(:'transaction_tracer.transaction_threshold' => -1.0) do
      Transactioner.new.do_it
    end

    transmit_data

    result = $collector.calls_for('transaction_sample_data')
    assert_equal 1, result.length
    assert_equal "Controller/MarshallingTest::Transactioner/do_it", result.first.metric_name
  end

  class Transactioner
    include NewRelic::Agent::Instrumentation::ControllerInstrumentation

    def do_it
    end

    add_transaction_tracer :do_it
  end

  def transmit_data
    NewRelic::Agent.instance.send(:transmit_data)
  end
end
