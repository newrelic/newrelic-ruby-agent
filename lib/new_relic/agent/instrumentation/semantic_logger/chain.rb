# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module SemanticLogger::Appenders::Chain
    def self.instrument!
      ::SemanticLogger::Appenders.class_eval do
        include NewRelic::Agent::Instrumentation::SemanticLogger::Appenders

        alias_method(:log_without_new_relic, :log)

        def log(log)
          log_with_new_relic(log) do
            log_without_new_relic(log)
          end
        end
      end
    end
  end
end
