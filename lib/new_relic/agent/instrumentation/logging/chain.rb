# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Logging::Chain
    def self.instrument!
      ::Logging::Logger.class_eval do
        include NewRelic::Agent::Instrumentation::Logging::Logger

        alias_method(:log_event_without_new_relic, :log_event)

        def log_event(event)
          log_event_with_new_relic(event) do
            log_event_without_new_relic(event)
          end
        end
      end
    end
  end
end
