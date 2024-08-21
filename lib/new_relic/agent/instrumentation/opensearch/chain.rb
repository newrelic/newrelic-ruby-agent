# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module OpenSearch::Chain
    def self.instrument!
      ::OpenSearch::Transport::Client.class_eval do
        include NewRelic::Agent::Instrumentation::OpenSearch

        alias_method(:perform_request_without_tracing, :perform_request)

        def perform_request(*args)
          perform_request_with_tracing(*args) do
            perform_request_without_tracing(*args)
          end
        end
      end
    end
  end
end
