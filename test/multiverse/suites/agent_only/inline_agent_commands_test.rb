# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'newrelic_rpm'

class InlineAgentCommandsTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  # The agent instance (and its executed command ids) survives across tests, so each test uses its own id.
  def stop_profiler_command(id)
    [id, {'name' => 'stop_profiler', 'arguments' => {'profile_id' => -1, 'report_data' => false}}]
  end

  def test_handles_a_command_from_the_metric_data_response
    $collector.stub('metric_data', [stop_profiler_command(801)])

    NewRelic::Agent.agent.send(:transmit_data)

    assert_command_results_sent_for(801)
  end

  def test_ignores_a_command_on_an_event_harvest_response
    $collector.stub('analytic_event_data', [stop_profiler_command(802)])
    in_transaction {}

    run_harvest

    assert_empty $collector.calls_for('agent_command_results')
  end

  def test_handles_commands_wrapped_in_an_agent_commands_key
    $collector.stub('metric_data', {'agent_commands' => [stop_profiler_command(803)]})

    NewRelic::Agent.agent.send(:transmit_data)

    assert_command_results_sent_for(803)
  end

  def test_a_redelivered_command_runs_once
    $collector.stub('metric_data', [stop_profiler_command(804)])

    2.times { NewRelic::Agent.agent.send(:transmit_data) }

    assert_equal 1, $collector.calls_for('agent_command_results').size
  end

  def test_does_not_poll_get_agent_commands
    run_harvest

    assert_empty $collector.calls_for('get_agent_commands')
  end

  def assert_command_results_sent_for(id)
    results = $collector.calls_for('agent_command_results')

    assert_equal 1, results.size
    assert_equal({id.to_s => {}}, results.first.body[1])
  end
end
