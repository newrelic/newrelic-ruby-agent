# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'securerandom'

class SpanEventsTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  def test_span_events_are_submitted
    event = generate_event('test_event')
    NewRelic::Agent.instance.span_event_aggregator.append(event: event)

    NewRelic::Agent.agent.send(:harvest_and_send_analytic_event_data)

    last_event = last_span_event
    assert_equal event, last_event
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
    guid = generate_guid

    {
      'name' => name,
      'priority' => rand,
      'sampled' => false,
      'guid'    => guid,
      'traceId' => guid,
      'timestamp' => (Time.now.to_f * 1000).round,
      'duration' => rand,
      'category' => 'custom'
    }
  end

  def generate_guid
    SecureRandom.hex(16)
  end
end
