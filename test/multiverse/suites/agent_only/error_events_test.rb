# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

class ErrorEventsTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent do
    nr_freeze_time
  end

  def test_error_events_are_submitted
    txn = generate_errors

    NewRelic::Agent.agent.send(:harvest_and_send_error_event_data)

    intrinsics, _, _ = last_error_event

    assert_equal txn.best_name, intrinsics["transactionName"]
    assert_equal "RuntimeError", intrinsics["error.class"]
    assert_equal "Big Controller", intrinsics["error.message"]
    assert_equal false, intrinsics["error.expected"]
    assert_equal "TransactionError", intrinsics["type"]
    assert_equal txn.payload[:duration], intrinsics["duration"]
  end

  def test_error_events_honor_expected_option
    txn = generate_errors 1, expected: true

    NewRelic::Agent.agent.send(:harvest_and_send_error_event_data)

    intrinsics, _, _ = last_error_event

    assert_equal true, intrinsics["error.expected"]
  end

  def test_records_supportability_metrics
    with_config :'error_collector.max_event_samples_stored' => 10 do
      generate_errors 15

      NewRelic::Agent.agent.send(:harvest_and_send_error_event_data)

      assert_metrics_recorded({
        "Supportability/Events/TransactionError/Sent" => {:call_count => 10},
        "Supportability/Events/TransactionError/Seen" => {:call_count => 15}
      })
    end
  end

  def test_does_not_record_error_events_when_disabled
    with_config :'error_collector.capture_events' => false do
      NewRelic::Agent.config.notify_server_source_added
      generate_errors 5

      NewRelic::Agent.agent.send(:harvest_and_send_error_event_data)
      assert_equal(0, $collector.calls_for(:error_event_data).size)
    end
  end

  def test_does_not_record_error_events_after_error_collector_disabled_from_server
    with_config :'error_collector.enabled' => true do
      generate_errors 5

      with_server_source :'error_collector.enabled' => false do
        NewRelic::Agent.agent.send(:harvest_and_send_error_event_data)
      end
    end

    assert_equal(0, $collector.calls_for(:error_event_data).size)
  end

  def test_does_not_record_error_events_when_disabled_by_feature_gate

    $collector.stub('connect', {
      'agent_run_id'          => 1,
      'collect_error_events' => false
    })
    trigger_agent_reconnect

    generate_errors 5

    NewRelic::Agent.agent.send(:harvest_and_send_error_event_data)
    assert_equal(0, $collector.calls_for(:error_event_data).size)

    # reset the collect_error_events flag so that the ErrorEventAggregator
    # will be enabled for the next test
    $collector.stub('connect', {
      'agent_run_id'          => 1,
      'collect_error_events' => true
    })

    trigger_agent_reconnect
  end

  def test_error_events_created_outside_of_transaction
    NewRelic::Agent.notice_error RuntimeError.new "No Txn"
    NewRelic::Agent.agent.send(:harvest_and_send_error_event_data)

    intrinsics, _, _ = last_error_event

    assert_equal "TransactionError", intrinsics["type"]
    assert_in_delta Time.now.to_f, intrinsics["timestamp"], 0.001
    assert_equal "RuntimeError", intrinsics["error.class"]
    assert_equal "No Txn", intrinsics["error.message"]
  end

  def test_error_events_during_txn_abide_by_custom_attributes_config
    with_config(:'custom_attributes.enabled' => false) do
      generate_errors 1, {:foo => "bar"}
    end

    NewRelic::Agent.agent.send(:harvest_and_send_error_event_data)

    _, custom_attributes, _ = last_error_event

    assert_equal({}, custom_attributes)
  end

  def test_error_events_outside_txn_abide_by_custom_attributes_config
    with_config(:'custom_attributes.enabled' => false) do
      NewRelic::Agent.notice_error(RuntimeError.new("Big Controller"), {:foo => "bar"})
    end

    NewRelic::Agent.agent.send(:harvest_and_send_error_event_data)

    _, custom_attributes, _ = last_error_event

    assert_equal({}, custom_attributes)
  end

  def generate_errors num_errors = 1, options = {}
    in_transaction :transaction_name => "Controller/blogs/index" do |t|
      num_errors.times { t.notice_error RuntimeError.new("Big Controller"), options }
    end
  end

  def last_error_event
    post = last_error_event_post
    assert_equal(1, post.events.size)
    post.events.last
  end

  def last_error_event_post
    $collector.calls_for(:error_event_data).first
  end
end
