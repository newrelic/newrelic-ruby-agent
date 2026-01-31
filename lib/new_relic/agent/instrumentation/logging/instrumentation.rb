# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Logging
    module Logger
      INSTRUMENTATION_NAME = 'Logging'
      STANDARD_LEVELS = %w[DEBUG INFO WARN ERROR FATAL UNKNOWN].freeze

      def self.enabled?
        NewRelic::Agent.config[:'instrumentation.logging'] != 'disabled'
      end

      def log_event_with_new_relic(event)
        severity = ::Logging::LNAMES[event.level] || 'UNKNOWN'
        unless above_level_threshold?(event.level) && meets_forwarding_threshold?(severity)
          return yield if block_given?
        end

        # If sending to multiple loggers, decorate each log
        event.data = NewRelic::Agent::LocalLogDecorator.decorate(event.data)

        # Prevents duplicate NR events when the same log goes through multiple loggers
        if event.logger == @name
          begin
            mdc_data = capture_mdc_data
            NewRelic::Agent.record_instrumentation_invocation(INSTRUMENTATION_NAME)
            NewRelic::Agent.agent.log_event_aggregator.record_logging_event(event, severity, mdc_data)
          rescue => e
            NewRelic::Agent.logger.debug("Failed to capture Logging event: #{e.message}")
          end
        end

        yield if block_given?
      end

      private

      def above_level_threshold?(event_level)
        return true unless self.respond_to?(:level)

        event_level >= self.level
      end

      def meets_forwarding_threshold?(severity)
        # Allow all custom levels
        return true unless STANDARD_LEVELS.include?(severity.upcase)

        forwarding_level = NewRelic::Agent.config[:'application_logging.forwarding.log_level']
        forwarding_idx = STANDARD_LEVELS.index(forwarding_level.upcase)
        severity_idx = STANDARD_LEVELS.index(severity.upcase)

        severity_idx >= forwarding_idx
      end

      def capture_mdc_data
        ::Logging.mdc.context
      rescue => e
        NewRelic::Agent.logger.debug("Failed to capture Logging MDC data: #{e.message}")
        {}
      end
    end
  end
end
