# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'multiverse_helpers'

class ExclusiveTimeTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  class TracedClass
    include NewRelic::Agent::Instrumentation::ControllerInstrumentation
    include NewRelic::Agent::MethodTracer

    def outer
      advance_time 2
      inner_a
      inner_b
    end
    add_transaction_tracer :outer

    def inner_a
      advance_time 5
    end
    add_method_tracer :inner_a, 'inner_a', :metric => false

    def inner_b
      advance_time 10
    end
    add_method_tracer :inner_b, 'inner_b'


    def outer_nested
      advance_time 2
      inner_nested_a
    end
    add_transaction_tracer :outer_nested

    def inner_nested_a
      advance_time 5
      inner_nested_b
    end
    add_method_tracer :inner_nested_a, 'inner_nested_a', :metric => false

    def inner_nested_b
      advance_time 10
    end
    add_method_tracer :inner_nested_b, 'inner_nested_b'
  end


  def test_traced_node_without_metrics_dont_decrease_exclusive_time
    txn_name = 'Controller/ExclusiveTimeTest::TracedClass/outer'

    freeze_time

    traced = TracedClass.new
    traced.outer

    assert_metrics_recorded(
      txn_name => {
        :call_count => 1,
        :total_call_time => 2 + 5 + 10,
        :total_exclusive_time => 2 + 5
      },
      ['inner_b', txn_name] => {
        :call_count => 1,
        :total_call_time => 10,
        :total_exclusive_time => 10
      })
  end

  def test_exclusive_time_should_propagate_through_nodes_that_dont_record_metrics
    txn_name = 'Controller/ExclusiveTimeTest::TracedClass/outer_nested'

    freeze_time

    traced = TracedClass.new
    traced.outer_nested

    assert_metrics_recorded(
      txn_name => {
        :call_count => 1,
        :total_call_time => 2 + 5 + 10,
        :total_exclusive_time => 2 + 5
      },
      ['inner_nested_b', txn_name] => {
        :call_count => 1,
        :total_call_time => 10,
        :total_exclusive_time => 10
      })
  end

end
