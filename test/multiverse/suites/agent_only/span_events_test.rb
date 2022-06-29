# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class SpanEventsTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  def test_span_events_are_submitted
    with_config :'distributed_tracing.enabled' => true do
      NewRelic::Agent.config.notify_server_source_added
      event = generate_event('test_event')
      NewRelic::Agent.instance.span_event_aggregator.record(event: event)

      NewRelic::Agent.agent.send(:harvest_and_send_span_event_data)

      last_event = last_span_event
      assert_equal event, last_event
    end
  end

  def test_span_events_are_not_recorded_when_disabled_by_feature_gate
    with_config :'distributed_tracing.enabled' => true do
      connect_response = {
        'agent_run_id' => 1,
        'collect_span_events' => false
      }

      $collector.stub('connect', connect_response)

      trigger_agent_reconnect

      event = generate_event('test_event')

      NewRelic::Agent.instance.span_event_aggregator.record(event: event)
      NewRelic::Agent.agent.send(:harvest_and_send_span_event_data)

      assert_equal(0, $collector.calls_for(:span_event_data).size)
    end
  end

  def last_span_event
    post = last_span_event_post
    assert_equal(1, post.events.size)
    post.events.last
  end

  def last_span_event_post
    $collector.calls_for(:span_event_data).first
  end

  def generate_event(name, options = {})
    guid = fake_guid(16)
    [
      {
        'name' => name,
        'priority' => options[:priority] || rand,
        'sampled' => false,
        'guid' => guid,
        'traceId' => guid,
        'timestamp' => Process.clock_gettime(Process::CLOCK_REALTIME, :millisecond),
        'duration' => rand,
        'category' => 'custom'
      },
      {},
      {}
    ]
  end
end
