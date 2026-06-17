# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../data_container_tests'
require_relative '../common_aggregator_tests'
require 'new_relic/agent/span_event_aggregator'

module NewRelic
  module Agent
    class SpanEventAggregatorTest < Minitest::Test
      def setup
        @additional_config = {:'distributed_tracing.enabled' => true}
        NewRelic::Agent.config.add_config_for_testing(@additional_config)

        nr_freeze_process_time
        events = NewRelic::Agent.instance.events
        @event_aggregator = SpanEventAggregator.new(events)
      end

      def teardown
        NewRelic::Agent.config.remove_config(@additional_config)
        NewRelic::Agent.agent.drop_buffered_data
      end

      # Helpers for DataContainerTests

      def create_container
        @event_aggregator
      end

      def populate_container(sampler, n)
        n.times do |i|
          generate_event("whatever#{i}")
        end
      end

      include NewRelic::DataContainerTests

      # Helpers for CommonAggregatorTests

      def generate_event(name = 'operation_name', options = {})
        guid = fake_guid(16)

        event = [
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

        @event_aggregator.record(event: event)
      end

      def last_events
        aggregator.harvest![1]
      end

      def aggregator
        @event_aggregator
      end

      def name_for(event)
        event[0]['name']
      end

      def enabled_key
        :'span_events.enabled'
      end

      include NewRelic::CommonAggregatorTests

      def test_harvest_extracts_span_links_from_events
        guid = fake_guid(16)
        span_link = [{'type' => 'SpanLink', 'linkedSpanId' => 'abc', 'linkedTraceId' => 'def'}, {}, {}]
        event_with_links = [
          {'type' => 'Span', 'name' => 'op', 'guid' => guid, 'traceId' => guid, 'priority' => 1.0,
           'sampled' => false, 'timestamp' => 1000, 'duration' => 0.1, 'category' => 'generic'},
          {},
          {},
          [span_link]
        ]
        @event_aggregator.record(event: event_with_links)
        _, events = @event_aggregator.harvest!

        span_events = events.select { |e| e[0]['type'] == 'Span' }
        span_link_events = events.select { |e| e[0]['type'] == 'SpanLink' }

        assert_equal 1, span_events.length
        assert_equal 3, span_events[0].length
        assert_equal 1, span_link_events.length
        assert_equal 'abc', span_link_events[0][0]['linkedSpanId']
      end

      def test_harvest_span_links_do_not_affect_span_event_count
        2.times do
          guid = fake_guid(16)
          span_link = [{'type' => 'SpanLink', 'linkedSpanId' => 'abc', 'linkedTraceId' => 'def'}, {}, {}]
          event_with_links = [
            {'type' => 'Span', 'name' => 'op', 'guid' => guid, 'traceId' => guid, 'priority' => 1.0,
             'sampled' => false, 'timestamp' => 1000, 'duration' => 0.1, 'category' => 'generic'},
            {},
            {},
            [span_link]
          ]
          @event_aggregator.record(event: event_with_links)
        end
        metadata, events = @event_aggregator.harvest!

        assert_equal 2, metadata[:events_seen], 'reservoir should only count span events, not span links'
        assert_equal 4, events.length, '2 span events + 2 span link events'
      end

      def test_harvest_returns_events_unchanged_when_no_span_links
        2.times { generate_event }
        _, events = @event_aggregator.harvest!

        events.each do |event|
          assert_equal 3, event.length
        end
      end

      def test_span_links_are_dropped_with_their_parent_span
        with_config(:'span_events.max_samples_stored' => 1) do
          span_link = [{'type' => 'SpanLink', 'linkedSpanId' => 'abc', 'linkedTraceId' => 'def'}, {}, {}]
          low_priority_guid = fake_guid(16)
          low_priority_span_with_link = [
            {'type' => 'Span', 'name' => 'low', 'guid' => low_priority_guid, 'traceId' => low_priority_guid,
             'priority' => 1.0, 'sampled' => false, 'timestamp' => 1000, 'duration' => 0.1, 'category' => 'generic'},
            {},
            {},
            [span_link]
          ]
          high_priority_guid = fake_guid(16)
          high_priority_span = [
            {'type' => 'Span', 'name' => 'high', 'guid' => high_priority_guid, 'traceId' => high_priority_guid,
             'priority' => 2.0, 'sampled' => false, 'timestamp' => 1000, 'duration' => 0.1, 'category' => 'generic'},
            {},
            {}
          ]

          @event_aggregator.record(event: low_priority_span_with_link)
          @event_aggregator.record(event: high_priority_span)

          _, events = @event_aggregator.harvest!

          assert_equal 1, events.length, 'only the high-priority span should survive'
          assert_equal 'high', events[0][0]['name']
          assert_empty events.select { |e| e[0]['type'] == 'SpanLink' }, 'links from dropped span must not appear'
        end
      end

      def test_harvest_extracts_span_events_from_events
        guid = fake_guid(16)
        span_event = [{'type' => 'SpanEvent', 'span.id' => guid, 'trace.id' => guid, 'name' => 'TestEvent', 'timestamp' => 1000}, {}, {}]
        event_with_span_events = [
          {'type' => 'Span', 'name' => 'op', 'guid' => guid, 'traceId' => guid, 'priority' => 1.0,
           'sampled' => false, 'timestamp' => 1000, 'duration' => 0.1, 'category' => 'generic'},
          {},
          {},
          [span_event]
        ]
        @event_aggregator.record(event: event_with_span_events)
        _, events = @event_aggregator.harvest!

        span_events = events.select { |e| e[0]['type'] == 'Span' }
        span_event_events = events.select { |e| e[0]['type'] == 'SpanEvent' }

        assert_equal 1, span_events.length
        assert_equal 3, span_events[0].length
        assert_equal 1, span_event_events.length
        assert_equal 'TestEvent', span_event_events[0][0]['name']
      end

      def test_harvest_span_events_do_not_affect_span_event_count
        2.times do
          guid = fake_guid(16)
          span_event = [{'type' => 'SpanEvent', 'span.id' => guid, 'trace.id' => guid, 'name' => 'TestEvent', 'timestamp' => 1000}, {}, {}]
          event_with_span_events = [
            {'type' => 'Span', 'name' => 'op', 'guid' => guid, 'traceId' => guid, 'priority' => 1.0,
             'sampled' => false, 'timestamp' => 1000, 'duration' => 0.1, 'category' => 'generic'},
            {},
            {},
            [span_event]
          ]
          @event_aggregator.record(event: event_with_span_events)
        end
        metadata, events = @event_aggregator.harvest!

        assert_equal 2, metadata[:events_seen], 'reservoir should only count span events, not SpanEvent events'
        assert_equal 4, events.length, '2 span events + 2 SpanEvent events'
      end

      def test_harvest_returns_events_unchanged_when_no_span_events
        2.times { generate_event }
        _, events = @event_aggregator.harvest!

        events.each do |event|
          assert_equal 3, event.length
        end
      end

      def test_span_events_are_dropped_with_their_parent_span
        with_config(:'span_events.max_samples_stored' => 1) do
          guid = fake_guid(16)
          span_event = [{'type' => 'SpanEvent', 'span.id' => guid, 'trace.id' => guid, 'name' => 'LowPriorityEvent', 'timestamp' => 1000}, {}, {}]
          low_priority_span_with_event = [
            {'type' => 'Span', 'name' => 'low', 'guid' => guid, 'traceId' => guid,
             'priority' => 1.0, 'sampled' => false, 'timestamp' => 1000, 'duration' => 0.1, 'category' => 'generic'},
            {},
            {},
            [span_event]
          ]
          high_priority_guid = fake_guid(16)
          high_priority_span = [
            {'type' => 'Span', 'name' => 'high', 'guid' => high_priority_guid, 'traceId' => high_priority_guid,
             'priority' => 2.0, 'sampled' => false, 'timestamp' => 1000, 'duration' => 0.1, 'category' => 'generic'},
            {},
            {}
          ]

          @event_aggregator.record(event: low_priority_span_with_event)
          @event_aggregator.record(event: high_priority_span)

          _, events = @event_aggregator.harvest!

          assert_equal 1, events.length, 'only the high-priority span should survive'
          assert_equal 'high', events[0][0]['name']
          assert_empty events.select { |e| e[0]['type'] == 'SpanEvent' }, 'SpanEvent events from dropped span must not appear'
        end
      end

      def test_supportability_metrics_for_span_events
        # NOTE: with_config won't work here, as the underlying capacity value
        #       ends up inside of a cached callback, so we'll directly alter
        #       the aggregator buffer's capacity and revert the change
        #       afterwards in an ensure block
        original_capacity = aggregator.instance_variable_get(:@buffer).capacity

        seen = 25_000
        captured = 10_000
        aggregator.instance_variable_get(:@buffer).capacity = captured

        seen.times { generate_event }

        assert_equal captured, last_events.size
        assert_metrics_recorded({'Supportability/SpanEvent/TotalEventsSeen' => {call_count: seen}})
        assert_metrics_recorded({'Supportability/SpanEvent/TotalEventsSent' => {call_count: captured}})
        assert_metrics_recorded({'Supportability/SpanEvent/Discarded' => {call_count: (seen - captured)}})
      ensure
        aggregator.instance_variable_get(:@buffer).capacity = original_capacity
      end
    end
  end
end
