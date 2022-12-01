# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../../test_helper'
require 'new_relic/agent/instrumentation/custom_events_subscriber'

module NewRelic::Agent::Instrumentation
  class CustomEventsSubscriberTest < Minitest::Test
    TOPIC = 'abre los ojos'
    ID = 1138
    SUBSCRIBER = NewRelic::Agent::Instrumentation::CustomEventsSubscriber.new

    #
    # tests with stubbing
    #
    def test_start
      in_transaction do |txn|
        time = Time.now.to_f
        SUBSCRIBER.start(TOPIC, ID, {})
        segment = txn.segments.last

        assert_in_delta time, segment.start_time
        assert_equal "ActiveSupport/CustomEvents/#{TOPIC}", segment.name
      end
    end

    def test_start_when_not_traced
      SUBSCRIBER.state.stub :is_execution_traced?, false do
        in_transaction do |txn|
          SUBSCRIBER.start(TOPIC, ID, {})

          assert_empty txn.segments
        end
      end
    end

    def test_start_with_exception_raised
      logger = MiniTest::Mock.new

      NewRelic::Agent.stub :logger, logger do
        logger.expect :error, nil, [/Error during .* callback/]
        logger.expect :log_exception, nil, [:error, ArgumentError]

        in_transaction do |txn|
          NewRelic::Agent::Tracer.stub :start_transaction_or_segment, -> { raise 'kaboom' } do
            SUBSCRIBER.start(TOPIC, ID, {})
          end

          assert_equal 1, txn.segments.size
        end
      end
      logger.verify
    end

    def test_finish
      in_transaction do |txn|
        started_segment = NewRelic::Agent::Tracer.start_transaction_or_segment(name: TOPIC, category: :testing)
        SUBSCRIBER.push_segment(ID, started_segment)

        time = Time.now.to_f
        SUBSCRIBER.finish(TOPIC, ID, {})
        segment = txn.segments.last

        assert_in_delta time, segment.end_time
        assert_predicate(segment, :finished?)
      end
    end

    def test_finish_with_exception_payload
      skip_unless_minitest5_or_above

      noticed = false
      exception_object = StandardError.new
      NewRelic::Agent.stub :notice_error, ->(_) { noticed = true }, [exception_object] do
        SUBSCRIBER.finish(TOPIC, ID, {exception_object: exception_object})
      end

      assert noticed
    end

    def test_finish_with_exception_raised
      logger = MiniTest::Mock.new

      NewRelic::Agent.stub :logger, logger do
        logger.expect :error, nil, [/Error during .* callback/]
        logger.expect :log_exception, nil, [:error, RuntimeError]

        in_transaction do |txn|
          SUBSCRIBER.state.stub :is_execution_traced?, -> { raise 'kaboom' } do
            SUBSCRIBER.finish(TOPIC, ID, {})
          end

          assert_equal 1, txn.segments.size
        end
      end
      logger.verify
    end

    #
    # tests with ActiveSupport enabled
    #
    def test_an_actual_custom_event_taking_place
      unless defined?(::ActiveSupport::Notifications) && defined?(::ActiveSupport::IsolatedExecutionState)
        skip 'Skipping test as ActiveSupport is not present'
      end

      with_config(active_support_custom_events_topics: [TOPIC]) do
        require 'new_relic/agent/instrumentation/rails_notifications/custom_events'
        DependencyDetection.detect!

        in_transaction do |txn|
          ActiveSupport::Notifications.subscribe(TOPIC) { |_name, _started, _finished, _unique_id, _data| }
          ActiveSupport::Notifications.instrument(TOPIC, key: :value) do
            rand(1148)
          end

          assert_equal 2, txn.segments.size
          segment = txn.segments.last

          assert_equal "ActiveSupport/CustomEvents/#{TOPIC}", segment.name
        end
      end
    end
  end
end
