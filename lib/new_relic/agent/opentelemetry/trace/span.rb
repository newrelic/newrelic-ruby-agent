# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        class Span < ::OpenTelemetry::Trace::Span
          attr_accessor :finishable
          attr_reader :status

          def initialize(span_context: nil)
            @status = ::OpenTelemetry::Trace::Status.unset
            super
          end

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

          def recording?
            !finishable&.finished?
          end

          def name=(name)
            if recording?
              if finishable.is_a?(NewRelic::Agent::Transaction)
                finishable.overridden_name = name
              elsif finishable.is_a?(NewRelic::Agent::Transaction::Segment)
                finishable.instance_variable_set(:@name, name)
              end
            else
              NewRelic::Agent.logger.warn('Calling name= on a finished OpenTelemetry Span') unless recording?
            end
          end

          def status=(new_status)
            @status = new_status
            attrs = {'status.code' => new_status.code}
            attrs['status.description'] = new_status.description unless new_status.description.empty?

            NewRelic::Agent.add_custom_span_attributes(attrs)
          end
        end
      end
    end
  end
end
