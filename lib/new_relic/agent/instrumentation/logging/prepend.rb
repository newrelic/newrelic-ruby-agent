# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Logging::Logger::Prepend
    include NewRelic::Agent::Instrumentation::Logging::Logger

    def log_event(event)
      log_event_with_new_relic(event) { super }
    end
  end
end
