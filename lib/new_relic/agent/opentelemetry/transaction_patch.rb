# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module TransactionPatch
        def set_current_segment(new_segment)
          @current_segment_lock.synchronize do
            if new_segment&.respond_to?(:transaction) && new_segment.transaction
              span = find_or_create_span(new_segment)
              NewRelic::Agent::TransactionTimeAggregator.current_execution_context[:nr_otel_current_span] = span
            end
          end

          super
        end

        def remove_current_segment_by_thread_id(id)
          if id == NewRelic::Agent::TransactionTimeAggregator.current_execution_context_id
            NewRelic::Agent::TransactionTimeAggregator.current_execution_context[:nr_otel_current_span] = nil
          end

          super
        end

        def finish
          NewRelic::Agent::TransactionTimeAggregator.current_execution_context[:nr_otel_current_span] = nil

          super
        end

        def add_span_link(link)
          initial_segment&.add_span_link(link)
        end

        def span_links
          initial_segment&.span_links || NewRelic::EMPTY_ARRAY
        end

        # This method adds a SpanEvent event to the Transaction's initial segment.
        # A SpanEvent is used to denote a meaningful, singular point in a
        # Span's duration.
        def add_span_event_event(name, attributes: nil, timestamp: nil)
          initial_segment&.add_span_event_event(name, attributes: attributes, timestamp: timestamp)
        end

        # Used to reference SpanEvent events associated with the initial segment.
        def span_events
          initial_segment&.span_events || NewRelic::EMPTY_ARRAY
        end

        private

        def find_or_create_span(segment)
          if segment.instance_variable_defined?(:@otel_span)
            segment.instance_variable_get(:@otel_span)
          else
            begin
              span = Trace::Span.new(span_context: span_context_from_segment(segment))
              segment.instance_variable_set(:@otel_span, span)
              span
            rescue => e
              NewRelic::Agent.logger.debug("Failed to create NR OTel span: #{e}")
              nil
            end
          end
        end

        def span_context_from_segment(segment)
          ::OpenTelemetry::Trace::SpanContext.new(
            trace_id: segment.transaction.trace_id,
            span_id: segment.guid,
            remote: false
          )
        end
      end
    end
  end
end
