# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'app'

class RailsEventLoggerTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  def setup
    skip 'Rails.event requires Rails 8.1+' unless rails_event_available?

    @aggregator = NewRelic::Agent.agent.log_event_aggregator
  end

  def teardown
    @aggregator.reset!
  end

  def test_rails_event_notify_records_log_event
    Rails.event.notify('user.signup', user_id: 123, email: 'test@example.com')

    _, events = @aggregator.harvest!

    assert_equal 1, events.size, 'Expected one log event to be recorded'

    log_event = events.first.last

    assert_equal 'user.signup', log_event['event.name']
    assert_equal 123, log_event['event.user_id']
    assert_equal 'test@example.com', log_event['event.email']
    assert_equal 'UNKNOWN', log_event['level']
  end

  def test_rails_event_with_nested_payload
    Rails.event.notify('order.created',
      order_id: 456,
      items: {count: 3, total: 99.99},
      customer: {id: 789, name: 'John Doe'})

    _, events = @aggregator.harvest!

    assert_equal 1, events.size
    log_event = events.first.last

    assert_equal 'order.created', log_event['event.name']
    assert_equal 456, log_event['event.order_id']
    # Nested hashes should be recorded as-is
    assert_equal({count: 3, total: 99.99}, log_event['event.items'])
    assert_equal({id: 789, name: 'John Doe'}, log_event['event.customer'])
  end

  def test_rails_event_includes_timestamp
    before_time = (Time.now.to_f * 1_000).to_i # milliseconds as integer

    Rails.event.notify('test.timing')

    after_time = (Time.now.to_f * 1_000).to_i

    _, events = @aggregator.harvest!

    assert_equal 1, events.size

    log_event = events.first.last
    event_timestamp = log_event['event.timestamp']

    assert event_timestamp, 'event.timestamp should be present'
    assert_operator event_timestamp, :>=, before_time, 'event.timestamp should be after or equal to before_time'
    assert_operator event_timestamp, :<=, after_time, 'event.timestamp should be before or equal to after_time'
  end

  def test_rails_event_includes_source_location
    Rails.event.notify('test.source')

    _, events = @aggregator.harvest!

    assert_equal 1, events.size

    log_event = events.first.last

    assert log_event.key?('source.file'), 'source.file should be present'
    assert log_event.key?('source.line'), 'source.line should be present'
    assert_includes log_event['source.file'], 'rails_event_logger_test.rb'
  end

  def test_multiple_rails_events_recorded
    Rails.event.notify('event.one', value: 1)
    Rails.event.notify('event.two', value: 2)
    Rails.event.notify('event.three', value: 3)

    _, events = @aggregator.harvest!

    assert_equal 3, events.size, 'Expected three log events to be recorded'

    event_names = events.map { |e| e.last['event.name'] }

    assert_includes event_names, 'event.one'
    assert_includes event_names, 'event.two'
    assert_includes event_names, 'event.three'
  end

  def test_rails_event_with_custom_level_in_payload
    Rails.event.notify('error.occurred', level: 'ERROR', message: 'Something went wrong')

    _, events = @aggregator.harvest!

    assert_equal 1, events.size
    log_event = events.first.last

    assert_equal 'error.occurred', log_event['event.name']
    assert_equal 'ERROR', log_event['level']
  end

  def test_rails_event_with_nil_and_empty_values_excluded
    Rails.event.notify('test.exclusions',
      valid_value: 'present',
      nil_value: nil,
      empty_string: '',
      empty_array: [],
      empty_hash: {},
      zero: 0,
      false_value: false)

    _, events = @aggregator.harvest!
    log_event = events.first.last

    # Should include valid values
    assert_equal 'present', log_event['event.valid_value']
    assert_equal 0, log_event['event.zero']
    refute log_event['event.false_value']

    # Should exclude nil and empty values
    refute log_event.key?('event.nil_value')
    refute log_event.key?('event.empty_string')
    refute log_event.key?('event.empty_array')
    refute log_event.key?('event.empty_hash')
  end

  def test_supportability_metrics_recorded
    Rails.event.notify('test.metric')

    # Check that the instrumentation invocation was recorded
    # The metric is tracked when record_instrumentation_invocation is called
    metric_names = NewRelic::Agent.instance.stats_engine.to_h.keys.map(&:to_s)

    assert metric_names.any? { |name| name.include?('RailsEventLogger') },
      'Expected a RailsEventLogger supportability metric to be recorded'
  end

  private

  def rails_event_available?
    defined?(Rails) && Rails.respond_to?(:event) && Rails.event.respond_to?(:notify)
  end
end
