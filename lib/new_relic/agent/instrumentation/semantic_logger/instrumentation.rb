# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module SemanticLogger
    module Appenders
      INSTRUMENTATION_NAME = 'SemanticLogger'

      def self.enabled?
        NewRelic::Agent.config[:'instrumentation.semantic_logger'] != 'disabled'
      end

      def log_with_new_relic(log)
        NewRelic::Agent.record_instrumentation_invocation(INSTRUMENTATION_NAME)
        NewRelic::Agent.agent.log_event_aggregator.record_semantic_logger(log, log.level)

        log.message = NewRelic::Agent::LocalLogDecorator.decorate(log.message)
        
        yield
      end
    end
  end
end
