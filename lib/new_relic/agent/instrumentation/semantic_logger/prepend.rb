# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'instrumentation'

module NewRelic::Agent::Instrumentation
  module SemanticLogger::Logger::Prepend
    include NewRelic::Agent::Instrumentation::SemanticLogger::Logger

    def log(log)
      log_with_new_relic(log) { super }
    end
  end
end
