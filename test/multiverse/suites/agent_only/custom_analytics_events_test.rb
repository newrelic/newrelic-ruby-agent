# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class CustomAnalyticsEventsTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  def teardown
    $collector.unstub('connect')
  end

  def test_custom_analytics_events_are_submitted
    t0 = nr_freeze_process_time
    NewRelic::Agent.record_custom_event(:DummyType, :foo => :bar, :baz => :qux)

    NewRelic::Agent.agent.send(:harvest_and_send_custom_event_data)
    events = last_posted_events
    events.first[0].delete('priority')

    expected_event = [{'type' => 'DummyType', 'timestamp' => t0.to_i},
      {'foo' => 'bar', 'baz' => 'qux'}]
    assert_equal(expected_event, events.first)
  end

  def test_record_custom_event_returns_falsy_if_event_was_dropped
    max_samples = NewRelic::Agent.config[:'custom_insights_events.max_samples_stored']
    max_samples.times do
      NewRelic::Agent.record_custom_event(:DummyType, :foo => :bar)
    end

    result = NewRelic::Agent.record_custom_event(:DummyType, :foo => :bar)
    refute(result)
  end

  def test_record_doesnt_record_if_invalid_event_type
    bad_event_type = 'bad$news'
    good_event_type = 'good news'

    NewRelic::Agent.record_custom_event(bad_event_type, :foo => :bar)
    NewRelic::Agent.record_custom_event(good_event_type, :foo => :bar)

    NewRelic::Agent.agent.send(:harvest_and_send_custom_event_data)
    events = last_posted_events

    assert_equal(1, events.size)
    assert_equal(good_event_type, events.first[0]['type'])
  end

  def test_events_are_not_recorded_when_disabled_by_feature_gate
    connect_response = {
      'agent_run_id' => 1,
      'collect_custom_events' => false
    }

    $collector.stub('connect', connect_response)

    trigger_agent_reconnect

    NewRelic::Agent.record_custom_event('whatever', :foo => :bar)

    NewRelic::Agent.agent.send(:harvest_and_send_analytic_event_data)
    assert_equal(0, $collector.calls_for(:custom_event_data).size)
  end

  def test_post_includes_metadata
    10.times do |i|
      NewRelic::Agent.record_custom_event(:DummyType, :foo => :bar, :baz => :qux, :i => i)
    end

    NewRelic::Agent.agent.send(:harvest_and_send_custom_event_data)
    post = last_custom_event_post

    assert_equal({"reservoir_size" => 3000, "events_seen" => 10}, post.reservoir_metadata)
  end

  def last_custom_event_post
    posts = $collector.calls_for('custom_event_data')
    assert_equal(1, posts.size)
    posts.first
  end

  def last_posted_events
    last_custom_event_post.events
  end
end
