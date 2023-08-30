# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Instrumentation
      class StripeSubscriber
        DEFAULT_DESTINATIONS = AttributeFilter::DST_SPAN_EVENTS
        EVENT_ATTRIBUTES = %i[http_status method num_retries path request_id].freeze

        def is_execution_traced?
          NewRelic::Agent::Tracer.state.is_execution_traced?
        end

        def start_segment(event)
          return unless is_execution_traced?

          segment = Tracer.start_segment(name: metric_name(event))
          event.user_data[:newrelic_segment] = segment
        rescue => e
          NewRelic::Agent.logger.error("Error starting New Relic Stripe segment: #{e}")
        end

        def metric_name(event)
          "Stripe#{event.path} #{event.method}"
        end

        def finish_segment(event)
          begin
            return unless is_execution_traced?

            segment = event.user_data[:newrelic_segment]
            EVENT_ATTRIBUTES.each do |attribute|
              segment.add_agent_attribute("stripe_#{attribute}", event.send(attribute), DEFAULT_DESTINATIONS)
            end
          ensure
            segment.finish
          end
        rescue => e
          NewRelic::Agent.logger.error("Error finishing New Relic Stripe segment: #{e}")
        end
      end
    end
  end
end
