# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class CollectorExceptionHandlingTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent do
    NewRelic::Agent.agent.stubs(:sleep)
  end

  def after_setup
    # there's a call to sleep in handle_force_restart that we want to skip
    $collector.reset
  end


  RESTART_PAYLOAD       = { 'error_type' => 'NewRelic::Agent::ForceRestartException'    }
  DISCONNECT_PAYLOAD    = { 'error_type' => 'NewRelic::Agent::ForceDisconnectException' }
  RUNTIME_ERROR_PAYLOAD = { 'error_type' => 'RuntimeError'                              }


  def test_should_reconnect_on_force_restart_exception
    # We stub these exceptions because we want the EventLoop to exit with a
    # ForceRestartException the first time through, then (after reconnecting)
    # we force the disconnect so that this test will end cleanly.

    $collector.stub_exception('metric_data'       , RESTART_PAYLOAD   ).once
    $collector.stub_exception('get_agent_commands', DISCONNECT_PAYLOAD).once

    with_config(:data_report_period => 0) do
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
    $collector.stub_exception('metric_data', DISCONNECT_PAYLOAD).once

    with_config(:data_report_period => 0) do
      NewRelic::Agent.agent.deferred_work!({})
    end

    assert_equal(1, $collector.calls_for('connect').size)
    assert_equal(1, $collector.calls_for('metric_data').size)
  end

  def test_should_stop_reporting_after_force_disconnect_on_connect
    $collector.stub_exception('connect', DISCONNECT_PAYLOAD).once

    with_config(:data_report_period => 0) do
      NewRelic::Agent.agent.deferred_work!({})
    end

    assert_equal(1, $collector.calls_for('connect').size)
  end

  def test_should_reconnect_on_connect_exception
    $collector.stub_exception('connect', RUNTIME_ERROR_PAYLOAD).once
    $collector.stub_exception('metric_data', DISCONNECT_PAYLOAD).once

    with_config(:data_report_period => 0) do
      NewRelic::Agent.agent.deferred_work!({})
    end

    assert_equal(2, $collector.calls_for('connect').size)
  end

  def test_should_reconnect_on_get_redirect_host_exception
    $collector.stub_exception('get_redirect_host', RUNTIME_ERROR_PAYLOAD).once
    $collector.stub_exception('metric_data', DISCONNECT_PAYLOAD).once

    with_config(:data_report_period => 0) do
      NewRelic::Agent.agent.deferred_work!({})
    end

    assert_equal(2, $collector.calls_for('get_redirect_host').size)
    assert_equal(1, $collector.calls_for('connect').size)
  end
end
