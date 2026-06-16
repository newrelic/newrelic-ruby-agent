# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module AbstractSegmentPatch
        MAX_SPAN_LINKS = 100
        SPAN_LINKS_DROPPED_METRIC = 'Supportability/Ruby/SpanEvent/Links/Dropped'
        MAX_SPAN_EVENTS = 100
        SPAN_EVENTS_DROPPED_METRIC = 'Supportability/Ruby/SpanEvent/Events/Dropped'

        def add_span_link(link)
          @span_links ||= []
          if @span_links.size >= MAX_SPAN_LINKS
            NewRelic::Agent.record_metric(SPAN_LINKS_DROPPED_METRIC, 1)
            return
          end
          @span_links << link
        end

        def span_links
          instance_variable_defined?(:@span_links) ? @span_links : NewRelic::EMPTY_ARRAY
        end

        # This method adds SpanEvent events to a Span event/Segment.
        # A SpanEvent is used to denote a meaningful, singular point in a
        # Span's duration.
        def add_span_event(name, attributes: nil, timestamp: nil)
          @span_events ||= []

          if @span_events.size >= MAX_SPAN_EVENTS
            NewRelic::Agent.record_metric(SPAN_EVENTS_DROPPED_METRIC, 1)
            return
          end

          # Normalize to Float seconds at storage time.
          # OTel may pass Integer nanoseconds; New Relic uses Float seconds.
          ts = if timestamp.nil?
            Process.clock_gettime(Process::CLOCK_REALTIME)
          elsif timestamp.is_a?(Integer)
            timestamp / 1_000_000_000.0
          else
            timestamp
          end

          @span_events << {name: name, attributes: attributes, timestamp: ts}
        end

        # Used to reference SpanEvent events associated with a Span/Segment
        def span_events
          instance_variable_defined?(:@span_events) ? @span_events : NewRelic::EMPTY_ARRAY
        end

        def force_finish
          if instance_variable_defined?(:@otel_span)
            otel_span = instance_variable_get(:@otel_span)
            if otel_span.respond_to?(:finish) && !otel_span.instance_variable_get(:@finished)
              begin
                otel_span.finish

                return if finished?
              rescue => e
                NewRelic::Agent.logger.debug("Error finishing OpenTelemetry span during force_finish: #{e}")
              end
            end
          end

          super
        end
      end
    end
  end
end
