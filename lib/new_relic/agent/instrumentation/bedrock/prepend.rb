# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Bedrock::Prepend
    include NewRelic::Agent::Instrumentation::Bedrock

    def invoke_model(params = {}, options = {})
      invoke_model_with_new_relic(params, options) { super }
    end
  end

  # module BedrockRuntime::Prepend
  #   include NewRelic::Agent::Instrumentation::BedrockRuntime

  #   def invoke_model(*args, **kwargs)
  #     invoke_model_with_new_relic(*args, **kwargs) { super }
  #   end
  # end
end
