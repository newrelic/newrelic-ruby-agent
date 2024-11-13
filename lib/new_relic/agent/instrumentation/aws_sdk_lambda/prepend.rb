# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module AwsSdkLambda::Prepend
    include NewRelic::Agent::Instrumentation::AwsSdkLambda

    def invoke(*args)
      invoke_with_new_relic(*args) { super }
    end

    def invoke_async(*args)
      invoke_async_with_new_relic(*args) { super }
    end

    def invoke_with_response_stream(*args)
      invoke_with_response_stream_with_new_relic(*args) { super }
    end
  end
end
