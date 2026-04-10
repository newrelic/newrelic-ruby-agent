# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  class RailsEventLogSubscriber
    INSTRUMENTATION_NAME = 'RailsEventLogger'

    def self.enabled?
      NewRelic::Agent.config[:'instrumentation.rails_event_logger']
    end

    def initialize
      @event_filter = NewRelic::Agent.config[:'instrumentation.rails_event_logger.event_names']
      @filter_enabled = !@event_filter.empty?
    end

    # Called by Rails.event system for each event
    # @param event [Hash] Event hash with keys: :name, :payload, :tags, :context, :timestamp, :source_location
    def emit(event)
      # Filter events if configured
      return if @filter_enabled && !@event_filter.include?(event[:name])

      NewRelic::Agent.record_instrumentation_invocation(INSTRUMENTATION_NAME)
      NewRelic::Agent.agent.log_event_aggregator.record_rails_event(event)
    rescue => e
      NewRelic::Agent.logger.debug("Failed to capture Rails.event: #{e.message}")
    end

    # Check if already subscribed to Rails.event
    def self.subscribed?
      return false unless defined?(Rails) && Rails.respond_to?(:event)

      # rubocop:disable Performance/RedundantEqualityComparisonBlock
      Rails.event.subscribers.any? { |sub| sub.is_a?(self) }
      # rubocop:enable Performance/RedundantEqualityComparisonBlock
    end
  end
end
