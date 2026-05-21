# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/instrumentation/rails_event_log_subscriber'

module NewRelic::Agent::Instrumentation
  class RailsEventLogSubscriberTest < Minitest::Test
    def setup
      @subscriber = RailsEventLogSubscriber.new
      @aggregator = NewRelic::Agent.agent.log_event_aggregator
    end

    def teardown
      @aggregator.reset!
    end

    def test_emit_records_event_when_no_filter
      with_config(:'instrumentation.rails_event_logger.event_names' => []) do
        subscriber = RailsEventLogSubscriber.new
        event = create_test_event('user.signup', user_id: 123)

        subscriber.emit(event)

        _, events = @aggregator.harvest!

        assert_equal 1, events.size
        log_event = events.first.last

        assert_equal 'user.signup', log_event['event.name']
        assert_equal 123, log_event['event.user_id']
      end
    end

    def test_emit_records_event_when_name_matches_filter
      with_config(:'instrumentation.rails_event_logger.event_names' => ['user.signup', 'payment.processed']) do
        subscriber = RailsEventLogSubscriber.new
        event = create_test_event('user.signup', user_id: 123)

        subscriber.emit(event)

        _, events = @aggregator.harvest!

        assert_equal 1, events.size
        log_event = events.first.last

        assert_equal 'user.signup', log_event['event.name']
        assert_equal 123, log_event['event.user_id']
      end
    end

    def test_emit_ignores_event_when_name_not_in_filter
      with_config(:'instrumentation.rails_event_logger.event_names' => ['user.signup']) do
        subscriber = RailsEventLogSubscriber.new
        event = create_test_event('payment.processed', amount: 99.99)

        subscriber.emit(event)

        _, events = @aggregator.harvest!

        assert_empty events, 'Event should be filtered and not recorded'
      end
    end

    def test_emit_handles_errors_gracefully
      with_config(:'instrumentation.rails_event_logger.event_names' => []) do
        subscriber = RailsEventLogSubscriber.new
        event = create_test_event('error.event', data: 'test')

        logger_debug_called = false

        # Stub aggregator to raise an error
        @aggregator.stub :record_rails_event, -> { raise StandardError, 'boom' } do
          NewRelic::Agent.logger.stub :debug, ->(msg) { logger_debug_called = true if /Failed to capture Rails.event/.match?(msg) } do
            # Should not raise
            subscriber.emit(event)
          end
        end

        assert logger_debug_called, 'Should log debug message when error occurs'
      end
    end

    def test_emit_records_instrumentation_invocation
      with_config(:'instrumentation.rails_event_logger.event_names' => []) do
        subscriber = RailsEventLogSubscriber.new
        event = create_test_event('test.event', data: 'test')

        invocation_recorded = false
        NewRelic::Agent.stub :record_instrumentation_invocation, ->(name) {
          invocation_recorded = true

          assert_equal 'RailsEventLogger', name
        } do
          subscriber.emit(event)
        end

        assert invocation_recorded, 'Should record instrumentation invocation'

        # Verify event was also recorded
        _, events = @aggregator.harvest!

        assert_equal 1, events.size
      end
    end

    private

    def create_test_event(name, payload = {})
      {
        name: name,
        payload: payload,
        tags: {},
        context: {},
        timestamp: Time.now.to_f * 1_000_000_000, # nanoseconds
        source_location: {
          filepath: '/app/test.rb',
          lineno: 42,
          label: 'test_method'
        }
      }
    end
  end
end
