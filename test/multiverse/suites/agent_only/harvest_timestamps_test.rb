# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'newrelic_rpm'

class HarvestTimestampsTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  def test_resets_metric_data_timestamps_after_forking
    freeze_time

    t1 = advance_time 10

    simulate_fork
    NewRelic::Agent.after_fork

    t2 = advance_time 10
    trigger_metric_data_post

    metric_data_post = $collector.calls_for('metric_data').first
    start_ts, end_ts = metric_data_post[1..2]

    if RUBY_VERSION == '1.8.7'
      # 1.8 + JSON is finicky about comparing floats.
      # If the timestamps are within 0.001 seconds, it's Good Enough.
      assert_in_delta(t1.to_f, start_ts, 0.001)
      assert_in_delta(t2.to_f, end_ts, 0.001)
    else
      assert_equal(t1.to_f, start_ts)
      assert_equal(t2.to_f, end_ts)
    end
  end

  def test_start_timestamp_maintained_on_harvest_failure
    t0 = freeze_time.to_f

    simulate_fork
    NewRelic::Agent.after_fork

    $collector.stub('metric_data', {}, 503)
    t1 = advance_time(10).to_f
    trigger_metric_data_post
    first_post = last_metric_data_post

    $collector.reset
    t2 = advance_time(10).to_f
    trigger_metric_data_post
    second_post = last_metric_data_post

    if RUBY_VERSION == '1.8.7'
      # 1.8 + JSON is finicky about comparing floats.
      # If the timestamps are within 0.001 seconds, it's Good Enough.
      assert_in_delta(t0, first_post[1], 0.001)
      assert_in_delta(t1, first_post[2], 0.001)
      assert_in_delta(t0, second_post[1], 0.001)
      assert_in_delta(t2, second_post[2], 0.001)
    else
      assert_equal([t0, t1], first_post[1..2])
      assert_equal([t0, t2], second_post[1..2])
    end
  end

  def trigger_metric_data_post
    NewRelic::Agent.agent.send(:transmit_data)
  end

  def last_metric_data_post
    $collector.calls_for('metric_data').last
  end

  def simulate_fork
    NewRelic::Agent.instance.harvester.instance_variable_set(:@starting_pid, nil)
  end
end
