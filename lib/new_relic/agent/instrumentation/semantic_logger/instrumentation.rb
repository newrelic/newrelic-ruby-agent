# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module SemanticLogger
    module Logger
      INSTRUMENTATION_NAME = 'SemanticLogger'

      def self.enabled?
        NewRelic::Agent.config[:'instrumentation.semantic_logger'] != 'disabled'
      end

      def log_with_new_relic(log)
        NewRelic::Agent.record_instrumentation_invocation(INSTRUMENTATION_NAME)

        begin
          NewRelic::Agent.agent.log_event_aggregator.record_semantic_logger(log)
          log.message = NewRelic::Agent::LocalLogDecorator.decorate(log.message)
        rescue => e
          NewRelic::Agent.logger.debug("Failed to capture Semantic Logger event: #{e.message}")
        end

        yield if block_given?
      end
    end
  end
end
