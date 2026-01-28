# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Logging
    module Logger
      INSTRUMENTATION_NAME = "Logging"

      def self.enabled?
        NewRelic::Agent.config[:'instrumentation.logging'] != 'disabled'
      end

      def log_event_with_new_relic(event)
        # Prevents duplicates when the same event goes through multiple loggers
        return unless event.logger == @name
     
        severity = ::Logging::LNAMES[event.level]     

        NewRelic::Agent.record_instrumentation_invocation(INSTRUMENTATION_NAME)
        NewRelic::Agent.agent.log_event_aggregator.record_logging_event(event, severity)
        NewRelic::Agent::LocalLogDecorator.decorate(event.data)
      rescue => e                                                                                                                                       
        NewRelic::Agent.logger.debug("Failed to capture Logging event: #{e.message}")
      end                                                                       
    end
  end
end
