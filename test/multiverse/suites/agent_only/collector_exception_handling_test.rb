# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# RUBY-839 make sure there is no STDOUT chatter
require 'open3'

class CollectorExceptionHandlingTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  def test_should_reconnect_on_force_restart_exception
    $collector.reset

    payload = { 'error_type' => 'NewRelic::Agent::ForceRestartException' }
    $collector.stub_exception('metric_data', payload).once

    with_config(:data_report_period => 0) do
      worker_loop = NewRelic::Agent::WorkerLoop.new(:limit => 1)
      NewRelic::Agent.agent.stubs(:create_worker_loop).returns(worker_loop)
      # there's a call to sleep in handle_force_restart that we want to skip
      NewRelic::Agent.agent.stubs(:sleep)
      NewRelic::Agent.agent.deferred_work!({})
    end

    assert_equal(2, $collector.calls_for('connect').size)

    # We expect one metric_data post that the collector responds to with the
    # ForceRestartException, and then another that gets through successfully.
    metric_data_calls = $collector.calls_for('metric_data')
    assert_equal(2, metric_data_calls.size)
    refute_equal(metric_data_calls[0].run_id, metric_data_calls[1].run_id)
  end

  def test_should_stop_reporting_after_force_disconnect
    $collector.reset

    payload = { 'error_type' => 'NewRelic::Agent::ForceDisconnectException' }
    $collector.stub_exception('metric_data', payload).once

    with_config(:data_report_period => 0) do
      NewRelic::Agent.agent.deferred_work!({})
    end

    assert_equal(1, $collector.calls_for('connect').size)
    assert_equal(1, $collector.calls_for('metric_data').size)
  end
end
