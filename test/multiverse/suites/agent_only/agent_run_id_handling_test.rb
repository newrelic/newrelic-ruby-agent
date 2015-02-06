# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'newrelic_rpm'

class AgentRunIdHandlingTest < Minitest::Test
  include MultiverseHelpers

  NON_NUMERIC_RUN_ID = 'some-crazy-non-integer-thing'

  setup_and_teardown_agent do
    $collector.stub('connect', { "agent_run_id" => NON_NUMERIC_RUN_ID })
  end

  # This test verifies that the Ruby agent is able to accept non-numeric values
  # of the agent run ID handed down by the collector in response to the connect
  # method. This is required for agent protocol version 14.
  def test_handles_non_numeric_agent_run_ids
    NewRelic::Agent.agent.send(:transmit_data)
    metric_data_post = $collector.calls_for('metric_data').last
    assert_equal(NON_NUMERIC_RUN_ID, metric_data_post[0])
  end

  # The sql_data endpoint sends the agent run ID as a query string parameter,
  # rather than embedded within the body, so make sure we handle that.
  def test_handles_non_numeric_agent_run_id_on_slow_sql_traces
    simulate_slow_sql_trace
    sql_data_post = $collector.calls_for('sql_trace_data').last
    assert_equal(NON_NUMERIC_RUN_ID, sql_data_post.query_params['run_id'])
  end

  def simulate_slow_sql_trace
    in_transaction do
      agent.sql_sampler.notice_sql("select * from test", "Database/test/select", nil, 1.5)
    end
    NewRelic::Agent.agent.send(:harvest_and_send_slowest_sql)
  end
end
