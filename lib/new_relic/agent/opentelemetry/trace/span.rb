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

          # @api private
          def recording?
            # in OTel, the recording? method checks for the end time on a span
            # The closest method we have to this is finished? which exists on
            # both transactions and segments.
            !finishable&.finished?
          end

          # @api private
          def name=(name)
            if recording?
              # overridden_name has slightly higher precedence than
              # set_transaction_name, but still has a small chance of being
              # overruled by other transaction naming operations if a
              # @frozen_name has already been set. See Transaction#best_name.
              if finishable.is_a?(NewRelic::Agent::Transaction)
                finishable.overridden_name = name
              # New Relic doesn't allow customers to rename segments
              # so this method is just to deal with the OTel APIs that may
              # try to rename a span after it's created.
              elsif finishable.is_a?(NewRelic::Agent::Transaction::Segment)
                finishable.instance_variable_set(:@name, name)
              end
            else
              NewRelic::Agent.logger.warn('Calling name= on a finished OpenTelemetry Span')
            end
          end

          # @api private
          def status=(new_status)
            # When OTel spans are inititalized they get an unset status
            # During instrumentation, they may have this status overwrritten
            # with an ok or error status. Error statuses may also have a description
            @status = new_status
            attrs = {'status.code' => new_status.code}
            attrs['status.description'] = new_status.description unless new_status.description.empty?

            txn = finishable.is_a?(Transaction) ? finishable : finishable.transaction
            attrs.each { |k, v| txn.add_agent_attribute(k, v, AttributeFilter::DST_SPAN_EVENTS) }
          end

          INVALID = new(span_context: ::OpenTelemetry::Trace::SpanContext::INVALID)
        end
      end
    end
  end
end
