# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class ErrorEventsTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  def test_error_events_are_submitted
    txn_name = "Controller/blogs/index"

    txn = in_transaction :transaction_name => txn_name do |t|
      t.notice_error RuntimeError.new "Big Controller"
    end

    NewRelic::Agent.agent.send(:harvest_and_send_error_event_data)

    intrinsics, _, _ = last_error_event

    assert_equal txn_name, intrinsics["transactionName"]
    assert_equal "RuntimeError", intrinsics["error.class"]
    assert_equal "Big Controller", intrinsics["error.message"]
    assert_equal "TransactionError", intrinsics["type"]
    assert_equal txn.payload[:duration], intrinsics["duration"]
  end

  def test_records_supportability_metrics
    with_config :'error_collector.max_event_samples_stored' => 10 do
      txn_name = "Controller/blogs/index"

      in_transaction :transaction_name => txn_name do |t|
        15.times do
          t.notice_error RuntimeError.new "Big Controller"
        end
      end

      NewRelic::Agent.agent.send(:harvest_and_send_error_event_data)

      assert_metrics_recorded({
        "Supportability/Events/TransactionError/Sent" => {:call_count => 1, :total_call_time => 10},
        "Supportability/Events/TransactionError/Seen" => {:call_count => 1, :total_call_time => 15}
      })
    end
  end

  def last_error_event
    post = last_error_event_post
    assert_equal(1, post.error_events.size)
    post.error_events.last
  end

  def last_error_event_post
    $collector.calls_for('error_event_data').first
  end
end
