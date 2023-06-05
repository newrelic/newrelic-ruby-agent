# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../../test_helper'

class NewRelic::Agent::MethodTracer::TraceExecutionScopedTest < Minitest::Test
  require 'new_relic/agent/method_tracer'
  include NewRelic::Agent::MethodTracer

  def setup
    NewRelic::Agent.agent.stats_engine.clear_stats
  end

  def teardown
    reset_buffers_and_caches
  end

  def test_metric_recording_in_non_nested_transaction
    in_transaction('outer') do
      trace_execution_scoped(%w[foo bar]) do
        # erm
      end
    end

    expected_values = {:call_count => 1}

    assert_metrics_recorded_exclusive(
      %w[foo outer] => expected_values,
      'foo' => expected_values,
      'bar' => expected_values,
      'outer' => expected_values,
      'Supportability/API/trace_execution_scoped' => expected_values,
      'OtherTransactionTotalTime' => expected_values,
      'OtherTransactionTotalTime/outer' => expected_values,
      'DurationByCaller/Unknown/Unknown/Unknown/Unknown/all' => expected_values,
      'Supportability/API/recording_web_transaction?' => expected_values,
      'DurationByCaller/Unknown/Unknown/Unknown/Unknown/allOther' => expected_values
    )
  end

  def test_metric_recording_in_nested_transactions
    in_transaction('Controller/outer_txn') do
      in_transaction('Controller/inner_txn') do
        trace_execution_scoped(%w[foo bar]) do
          # erm
        end
      end
    end

    expected_values = {:call_count => 1}

    assert_metrics_recorded_exclusive(
      'HttpDispatcher' => expected_values,
      'Controller/inner_txn' => expected_values,

      'Nested/Controller/inner_txn' => expected_values,
      ['Nested/Controller/inner_txn', 'Controller/inner_txn'] => expected_values,
      'Nested/Controller/outer_txn' => expected_values,
      ['Nested/Controller/outer_txn', 'Controller/inner_txn'] => expected_values,

      ['foo', 'Controller/inner_txn'] => expected_values,
      'foo' => expected_values,
      'bar' => expected_values,
      'Supportability/API/trace_execution_scoped' => expected_values,
      'OtherTransactionTotalTime' => expected_values,
      'OtherTransactionTotalTime/Controller/inner_txn' => expected_values,
      'DurationByCaller/Unknown/Unknown/Unknown/Unknown/all' => expected_values,
      'Supportability/API/recording_web_transaction?' => expected_values,
      'DurationByCaller/Unknown/Unknown/Unknown/Unknown/allOther' => expected_values
    )
  end

  def test_metric_recording_in_3_nested_transactions
    in_transaction('Controller/outer_txn') do
      in_transaction('Controller/middle_txn') do
        in_transaction('Controller/inner_txn') do
          # erm
        end
      end
    end

    assert_metrics_recorded([
      'Controller/inner_txn',
      'Nested/Controller/inner_txn',
      'Nested/Controller/middle_txn',
      'Nested/Controller/outer_txn'
    ])
  end

  def test_metric_recording_inside_transaction
    in_transaction('outer') do
      trace_execution_scoped(%w[foo bar]) do
        # erm
      end
    end

    expected_values = {:call_count => 1}

    assert_metrics_recorded_exclusive(
      'outer' => expected_values,
      'foo' => expected_values,
      %w[foo outer] => expected_values,
      'bar' => expected_values,
      'Supportability/API/trace_execution_scoped' => expected_values,
      'OtherTransactionTotalTime' => expected_values,
      'OtherTransactionTotalTime/outer' => expected_values,
      'DurationByCaller/Unknown/Unknown/Unknown/Unknown/all' => expected_values,
      'Supportability/API/recording_web_transaction?' => expected_values,
      'DurationByCaller/Unknown/Unknown/Unknown/Unknown/allOther' => expected_values
    )
  end

  def test_metric_recording_with_metric_option_false
    options = {:metric => false, :scoped_metric => false}

    in_transaction('outer') do
      trace_execution_scoped(%w[foo bar], options) do
        # erm
      end
    end

    expected_values = {:call_count => 1}

    assert_metrics_recorded_exclusive(
      'outer' => expected_values,
      'Supportability/API/trace_execution_scoped' => expected_values,
      'OtherTransactionTotalTime' => expected_values,
      'OtherTransactionTotalTime/outer' => expected_values,
      'DurationByCaller/Unknown/Unknown/Unknown/Unknown/all' => expected_values,
      'Supportability/API/recording_web_transaction?' => expected_values,
      'DurationByCaller/Unknown/Unknown/Unknown/Unknown/allOther' => expected_values
    )
  end

  def test_trace_execution_scoped_calculates_exclusive_time
    nr_freeze_process_time
    in_transaction('txn') do
      trace_execution_scoped(['parent']) do
        advance_process_time(10)
        trace_execution_scoped(['child']) do
          advance_process_time(10)
        end
      end
    end

    assert_metrics_recorded_exclusive(
      'txn' => {
        :call_count => 1
      },
      'parent' => {
        :call_count => 1,
        :total_call_time => 20,
        :total_exclusive_time => 10
      },
      %w[parent txn] => {
        :call_count => 1,
        :total_call_time => 20,
        :total_exclusive_time => 10
      },
      'child' => {
        :call_count => 1,
        :total_call_time => 10,
        :total_exclusive_time => 10
      },
      %w[child txn] => {
        :call_count => 1,
        :total_call_time => 10,
        :total_exclusive_time => 10
      },
      'Supportability/API/trace_execution_scoped' => {
        call_count: 2
      },
      'OtherTransactionTotalTime' => {
        :call_count => 1
      },
      'OtherTransactionTotalTime/txn' => {
        :call_count => 1
      },
      'DurationByCaller/Unknown/Unknown/Unknown/Unknown/all' => {
        :call_count => 1
      },
      'Supportability/API/recording_web_transaction?' => {
        :call_count => 1
      },
      'DurationByCaller/Unknown/Unknown/Unknown/Unknown/allOther' => {
        :call_count => 1
      }
    )
  end

  def test_trace_execution_scoped_disabled
    # make sure the method doesn't beyond the abort
    self.expects(:set_if_nil).never
    ran = false
    value = trace_execution_scoped(nil, {:options => 'hash'}) do
      ran = true
      1172
    end

    assert ran, 'should run contents of block'
    assert_equal 1172, value, 'should return contents of block'
  end

  def test_trace_execution_scope_runs_passed_block_and_returns_its_value
    value = trace_execution_scoped(%w[metric array], {}) do
      1172
    end

    assert_equal 1172, value, 'should return the contents of the block'
  end

  def test_trace_execution_scoped_does_not_swallow_errors
    assert_raises(RuntimeError) do
      trace_execution_scoped(%w[metric array], {}) do
        raise 'raising a test error'
      end
    end
  end

  private

  def mocked_object(name)
    object = mock(name)
    self.stubs(name).returns(object)
    object
  end

  def mocked_control
    mocked_object('control')
  end
end
