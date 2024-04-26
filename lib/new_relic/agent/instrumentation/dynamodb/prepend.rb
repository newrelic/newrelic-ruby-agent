# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Dynamodb::Prepend
    include NewRelic::Agent::Instrumentation::Dynamodb

    def build_request(*args)
      build_request_with_new_relic(*args) { super }
    end
  end
end
