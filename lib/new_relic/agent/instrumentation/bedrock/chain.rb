# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Bedrock::Chain
    def self.instrument!
      Aws::Bedrock::Client.class_eval do
        include NewRelic::Agent::Instrumentation::Bedrock

        alias_method(:invoke_model_without_new_relic, :invoke_model)

        def invoke_model(*args)
          invoke_model_with_new_relic(*args) do
            invoke_model_without_new_relic(*args)
          end
        end
      end
    end
  end
end
