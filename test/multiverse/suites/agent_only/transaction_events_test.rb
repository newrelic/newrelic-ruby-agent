# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class TransactionEventsTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  def test_transaction_event_error_flag_is_set
    in_transaction :transaction_name => "Controller/blogs/index" do |t|
      t.notice_error RuntimeError.new "Big Controller"
    end

    NewRelic::Agent.agent.send(:harvest_and_send_analytic_event_data)

    intrinsics, _, _ = last_transaction_event

    assert intrinsics["error"], "Expected the error flag to be true"
  end

  def last_transaction_event
    post = last_transaction_event_post
    assert_equal(1, post.events.size)
    post.events.last
  end

  def last_transaction_event_post
    $collector.calls_for(:analytic_event_data).first
  end
end
