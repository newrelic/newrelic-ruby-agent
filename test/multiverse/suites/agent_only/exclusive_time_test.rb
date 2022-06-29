# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class ExclusiveTimeTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  def test_exclusive_time_on_unscoped_metric_should_be_zero_if_scoped_metric_matches
    traced_class = Class.new do
      include NewRelic::Agent::Instrumentation::ControllerInstrumentation
      include NewRelic::Agent::MethodTracer

      def outer_a
        advance_process_time 2
        outer_b
      end
      add_transaction_tracer :outer_a, :class_name => 'traced'

      def outer_b
        advance_process_time 5
        inner
      end
      add_transaction_tracer :outer_b, :class_name => 'traced'

      def inner
        advance_process_time 10
      end
      add_method_tracer :inner, 'inner'
    end

    nr_freeze_process_time
    traced_class.new.outer_a

    txn_name = 'Controller/traced/outer_b'
    assert_metrics_recorded(
      txn_name => {
        :call_count => 1,
        :total_call_time => 2 + 5 + 10,
        :total_exclusive_time => 0
      },
      ['Nested/Controller/traced/outer_a', txn_name] => {
        :call_count => 1,
        :total_call_time => 2 + 5 + 10,
        :total_exclusive_time => 2
      },
      ['Nested/Controller/traced/outer_b', txn_name] => {
        :call_count => 1,
        :total_call_time => 5 + 10,
        :total_exclusive_time => 5
      },
      ['inner', txn_name] => {
        :call_count => 1,
        :total_call_time => 10,
        :total_exclusive_time => 10
      }
    )
  end

  def test_exclusive_time_on_unscoped_metric_should_be_non_zero_if_no_nested_transaction
    traced_class = Class.new do
      include NewRelic::Agent::Instrumentation::ControllerInstrumentation
      include NewRelic::Agent::MethodTracer

      def outer
        advance_process_time 2
        inner
      end
      add_transaction_tracer :outer, :class_name => 'traced'

      def inner
        advance_process_time 10
      end
      add_method_tracer :inner, 'inner'
    end

    nr_freeze_process_time
    traced_class.new.outer

    txn_name = 'Controller/traced/outer'
    assert_metrics_recorded(
      txn_name => {
        :call_count => 1,
        :total_call_time => 2 + 10,
        :total_exclusive_time => 2
      },
      ['inner', txn_name] => {
        :call_count => 1,
        :total_call_time => 10,
        :total_exclusive_time => 10
      }
    )
  end
end
