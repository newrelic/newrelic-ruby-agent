# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'newrelic_rpm'

class HarvestTimestampsTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  def test_resets_metric_data_timestamps_after_forking
    nr_freeze_process_time

    t1 = advance_process_time(10)

    simulate_fork
    NewRelic::Agent.after_fork

    t2 = advance_process_time(10)
    trigger_metric_data_post

    metric_data_post = $collector.calls_for('metric_data').first
    start_ts, end_ts = metric_data_post[1..2]

    assert_equal(t1, start_ts)
    assert_equal(t2, end_ts)
  end

  def test_start_timestamp_maintained_on_harvest_failure
    t0 = nr_freeze_process_time

    simulate_fork
    NewRelic::Agent.after_fork

    $collector.stub('metric_data', {}, 503)
    t1 = advance_process_time(10)
    trigger_metric_data_post
    first_post = last_metric_data_post

    $collector.reset
    t2 = advance_process_time(10)
    trigger_metric_data_post
    second_post = last_metric_data_post

    assert_equal([t0, t1], first_post[1..2])
    assert_equal([t0, t2], second_post[1..2])
  end

  def trigger_metric_data_post
    NewRelic::Agent.agent.send(:transmit_data)
  end

  def last_metric_data_post
    $collector.calls_for('metric_data').last
  end

  def simulate_fork
    NewRelic::Agent.instance.instance_variable_get(:@harvester).instance_variable_set(:@starting_pid, nil)
  end
end
