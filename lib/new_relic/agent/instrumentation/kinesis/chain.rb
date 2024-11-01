# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Kinesis::Chain
    def self.instrument!
      ::Kinesis.class_eval do
        include NewRelic::Agent::Instrumentation::Kinesis

        alias_method(:build_request_without_new_relic, :build_request)

        def build_request(*args)
          build_request_with_new_relic(*args) do
            build_request_without_new_relic(*args)
          end
        end
      end
    end
  end
end
