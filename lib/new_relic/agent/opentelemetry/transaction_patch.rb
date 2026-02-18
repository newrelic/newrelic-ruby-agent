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
              Thread.current[:nr_otel_current_span] = span
            end
          end

          super
        end

        def remove_current_segment_by_thread_id(id)
          if id == Thread.current.object_id
            Thread.current[:nr_otel_current_span] = nil
          end

          super
        end

        def finish
          Thread.current[:nr_otel_current_span] = nil

          super
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
