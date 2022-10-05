# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class TransactionEventsTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  def test_transaction_event_has_priority
    in_transaction(:transaction_name => "Controller/blogs/index") {}

    NewRelic::Agent.agent.send(:harvest_and_send_analytic_event_data)

    intrinsics, _, _ = last_transaction_event

    assert intrinsics["priority"].is_a?(Numeric), "Expected event to have priority"
  end

  def test_transaction_event_error_flag_is_set
    in_transaction(:transaction_name => "Controller/blogs/index") do |t|
      t.notice_error(RuntimeError.new("Big Controller"))
    end

    NewRelic::Agent.agent.send(:harvest_and_send_analytic_event_data)

    intrinsics, _, _ = last_transaction_event

    assert intrinsics["error"], "Expected the error flag to be true"
  end

  def test_transaction_events_abide_by_custom_attributes_config
    with_config(:'custom_attributes.enabled' => false) do
      in_transaction(:transaction_name => "Controller/blogs/index") do |t|
        t.add_custom_attributes(:foo => "bar")
      end
    end

    NewRelic::Agent.agent.send(:harvest_and_send_analytic_event_data)

    _, custom_attributes, _ = last_transaction_event

    assert_empty(custom_attributes)
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
