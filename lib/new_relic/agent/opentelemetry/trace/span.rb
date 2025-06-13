# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        class Span < ::OpenTelemetry::Trace::Span
          attr_accessor :finishable

          def finish(end_timestamp: nil)
            finishable&.finish
          end

          def set_attribute(key, value)
            NewRelic::Agent.add_custom_span_attributes(key => value)
          end

          def add_attributes(attributes)
            NewRelic::Agent.add_custom_span_attributes(attributes)
          end

          def record_exception(exception, attributes: nil)
            NewRelic::Agent.notice_error(exception, attributes: attributes)
          end
        end
      end
    end
  end
end
