# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        class Tracer < ::OpenTelemetry::Trace::Tracer
          def initialize(name = nil, version = nil)
            @name = name || ''
            @version = version || ''
          end

          def in_span(name, attributes: nil, links: nil, start_timestamp: nil, kind: nil)
            case kind
            when :internal
              begin
                segment = NewRelic::Agent::Tracer.start_segment(name: name)
                span = FakeSpan.new(segment: segment, transaction: segment.transaction)

                ::OpenTelemetry::Trace.with_span(span) do
                  yield
                end
              ensure
                segment&.finish
              end
            else
              NewRelic::Agent.logger.debug("Span kind: #{kind} is not supported yet")
            end
          end
        end
      end
    end
  end
end
