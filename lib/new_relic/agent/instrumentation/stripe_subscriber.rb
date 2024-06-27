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
        PATH_PORTION_PATTERN = %r{^/([^/]+/[^/]+)(?:/|\z)}.freeze

        def start_segment(event)
          return unless is_execution_traced?

          segment = NewRelic::Agent::Tracer.start_segment(name: metric_name(event))
          event.user_data[:newrelic_segment] = segment
        rescue => e
          NewRelic::Agent.logger.error("Error starting New Relic Stripe segment: #{e}")
        end

        def finish_segment(event)
          return unless is_execution_traced?

          segment = remove_and_return_nr_segment(event)
          add_stripe_attributes(segment, event)
          add_custom_attributes(segment, event)
        rescue => e
          NewRelic::Agent.logger.error("Error finishing New Relic Stripe segment: #{e}")
        ensure
          segment&.finish
        end

        private

        def is_execution_traced?
          NewRelic::Agent::Tracer.state.is_execution_traced?
        end

        def metric_name(event)
          # Grab only the first 2 items from the slash (/) delimited event path.
          # These items are the API version string and the category. Grabbing
          # any more of the path will result in unique method names that will
          # easily grow to be too numerous to sort through in the UI and
          # possibly even violate default New Relic metric count thresholds.
          # See newrelic/newrelic-ruby-agent#2654 and
          # newrelic/newrelic-ruby-agent#2709 for more details.
          #
          # In Ruby v3.4 benchmarks, using regex to get at the first two path
          # elements was seen as more performant than using String#split.
          #
          # Regex legend:
          #
          # ^ = starts with
          # / = a literal '/'
          # () = capture
          # (?:) = don't capture
          # [^/]+ = 1 or more characters that are not '/'
          # /|\z = a literal '/' OR the end of the string
          path_portion = event.path =~ PATH_PORTION_PATTERN ? Regexp.last_match(1) : NewRelic::UNKNOWN
          "Stripe/#{path_portion}/#{event.method}"
        end

        def add_stripe_attributes(segment, event)
          EVENT_ATTRIBUTES.each do |attribute|
            segment.add_agent_attribute("stripe_#{attribute}", event.send(attribute), DEFAULT_DESTINATIONS)
          end
        end

        def add_custom_attributes(segment, event)
          return if NewRelic::Agent.config[:'stripe.user_data.include'].empty?

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

        def remove_and_return_nr_segment(event)
          segment = event.user_data[:newrelic_segment]
          event.user_data.delete(:newrelic_segment)

          segment
        end
      end
    end
  end
end
