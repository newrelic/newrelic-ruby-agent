# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../attributes'

module NewRelic
  module Agent
    module OpenTelemetry
      module SpanEventPrimitivePatch
        SPAN_LINK_TYPE = 'SpanLink'
        ID_KEY = 'id'
        LINKED_SPAN_ID_KEY = 'linkedSpanId'
        LINKED_TRACE_ID_KEY = 'linkedTraceId'
        TRACE_DOT_ID_KEY = 'trace.id'
        SPAN_EVENT_TYPE = 'SpanEvent'
        SPAN_DOT_ID_KEY = 'span.id'

        def for_segment(segment)
          span_data = super
          span_data = attach_span_links(span_data, segment)
          attach_span_event_events(span_data, segment)
        end

        def for_external_request_segment(segment)
          span_data = super
          span_data = attach_span_links(span_data, segment)
          attach_span_event_events(span_data, segment)
        end

        def for_datastore_segment(segment)
          span_data = super
          span_data = attach_span_links(span_data, segment)
          attach_span_event_events(span_data, segment)
        end

        private

        def attach_span_links(span_data, segment)
          links = for_span_links(segment)
          links.empty? ? span_data : span_data << links
        end

        def for_span_links(segment)
          return [] if segment.span_links.empty?

          segment.span_links.map do |link|
            ctx = link.span_context
            intrinsics = {
              SpanEventPrimitive::TYPE_KEY => SPAN_LINK_TYPE,
              SpanEventPrimitive::TIMESTAMP_KEY => milliseconds_since_epoch(segment),
              ID_KEY => segment.guid,
              TRACE_DOT_ID_KEY => segment.transaction.trace_id,
              LINKED_SPAN_ID_KEY => ctx.hex_span_id,
              LINKED_TRACE_ID_KEY => ctx.hex_trace_id
            }
            [intrinsics, sanitize_event_attributes(link.attributes), {}]
          end
        end

        # The event argument in this case refers to the Span/Segment associated
        # with the SpanEvent.
        def attach_span_event_events(span_data, segment)
          span_events = for_span_events(segment)
          return span_data if span_events.empty?

          if span_data.length > 3
            span_data[3].concat(span_events)
          else
            span_data << span_events
          end

          span_data
        end

        def for_span_events(segment)
          return [] if segment.span_events.empty?

          segment.span_events.map do |evt|
            intrinsics = {
              SpanEventPrimitive::TYPE_KEY => SPAN_EVENT_TYPE,
              # This is the same formula as milliseconds_since_epoch, but without
              # the segment.start_time value
              SpanEventPrimitive::TIMESTAMP_KEY => Integer(evt[:timestamp].to_f * 1000.0),
              SPAN_DOT_ID_KEY => segment.guid,
              TRACE_DOT_ID_KEY => segment.transaction.trace_id,
              SpanEventPrimitive::NAME_KEY => evt[:name]
            }
            [intrinsics, sanitize_event_attributes(evt[:attributes]), {}]
          end
        end

        def sanitize_event_attributes(attrs)
          return NewRelic::EMPTY_HASH if attrs.nil? || attrs.empty?

          filter = NewRelic::Agent.instance.attribute_filter
          attr_obj = Attributes.new(filter)
          attr_obj.merge_custom_attributes(attrs)
          attr_obj.custom_attributes_for(AttributeFilter::DST_SPAN_EVENTS)
        end
      end
    end
  end
end
