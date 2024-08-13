# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module OpenSearch::Prepend
    include NewRelic::Agent::Instrumentation::OpenSearch

    def perform_request(*args)
      perform_request_with_tracing(*args) { super }
    end
  end
end
