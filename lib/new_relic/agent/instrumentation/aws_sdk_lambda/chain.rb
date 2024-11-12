# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module AwsSdkLambda::Chain
    def self.instrument!
      ::Aws::Lambda::Client.class_eval do
        include NewRelic::Agent::Instrumentation::AwsSdkLambda

        alias_method(:invoke_without_new_relic, :invoke)

        def invoke(*args)
          invoke_with_new_relic(*args) { invoke_without_new_relic(*args) }
        end

        alias_method(:invoke_async_without_new_relic, :invoke_async)

        def invoke_async(*args)
          invoke_async_with_new_relic(*args) { invoke_async_without_new_relic(*args) }
        end

        alias_method(:invoke_with_response_stream_without_new_relic, :invoke_with_response_stream)

        def invoke_with_response_stream(*args)
          invoke_with_response_stream_with_new_relic(*args) { invoke_with_response_stream_without_new_relic(*args) }
        end
      end
    end
  end
end
