# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Instrumentation
      class StripeSubscriber
        DEFAULT_DESTINATIONS = AttributeFilter::DST_SPAN_EVENTS
        EVENT_ATTRIBUTES = %i[http_status method num_retries path request_id].freeze
        ATTRIBUTE_NAMESPACE = 'stripe.user_data'
        ATTRIBUTE_FILTER_TYPES = %i[include exclude].freeze

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

        def add_stripe_attributes(segment, event)
          EVENT_ATTRIBUTES.each do |attribute|
            segment.add_agent_attribute("stripe_#{attribute}", event.send(attribute), DEFAULT_DESTINATIONS)
          end
        end

        def add_custom_attributes(segment, event)
          event.user_data.delete(:newrelic_segment)
          filtered_attributes = NewRelic::Agent::AttributePreFiltering.pre_filter_hash(event.user_data, nr_attribute_options)
          filtered_attributes.each do |key, value|
            segment.add_agent_attribute("stripe_user_data_#{key}", value, DEFAULT_DESTINATIONS)
          end
        end

        def nr_attribute_options
          ATTRIBUTE_FILTER_TYPES.each_with_object({}) do |type, opts|
            pattern =
              NewRelic::Agent::AttributePreFiltering.formulate_regexp_union(:"#{ATTRIBUTE_NAMESPACE}.#{type}")
            opts[type] = pattern if pattern
          end
        end

        def finish_segment(event)
          begin
            return unless is_execution_traced?

            segment = event.user_data[:newrelic_segment]
            add_stripe_attributes(segment, event)
            add_custom_attributes(segment, event)
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
