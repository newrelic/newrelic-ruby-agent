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
        severity = ::Logging::LNAMES[event.level]     

        NewRelic::Agent.record_instrumentation_invocation(INSTRUMENTATION_NAME)
        ::NewRelic::Agent.agent.log_event_aggregator.record_logging_event(event, severity)
        ::NewRelic::Agent::LocalLogDecorator.decorate(event.data)

        yield
      end
    end
  end
end
