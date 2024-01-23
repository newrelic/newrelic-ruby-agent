# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class LlmEvent
      class Embedding < NewRelic::Agent::LlmEvent
        EVENT_NAME = 'LlmEmbedding'

        def initialize (input: nil, request_model: nil, response_organization: nil, response_usage_total_tokens: nil, response_usage_prompt_tokens: nil, response_headers: nil, duration: nil, error: nil, **args)
          @input = input
          @request_model = request_model
          @response_organization = response_organization
          @response_usage_total_tokens = response_usage_total_tokens
          @response_usage_prompt_tokens = response_usage_prompt_tokens
          @response_headers = LlmEvent::ResponseHeaders.new
          @duration = duration
          @error = error
          super
        end

        def embedding_attributes
          {
            input: @input,
            request_model: @request_model,
            response_organization: @response_organization,
            response_usage_total_tokens: @response_usage_total_tokens,
            response_usage_prompt_tokens: @response_usage_prompt_tokens,
            response_headers: @response_headers, # may need to break down further
            duration: @duration,
            error: @error
          }.merge(llm_event_attributes)
        end

        def record
          NewRelic::Agent.record_custom_event(EVENT_NAME, embedding_attributes)
        end
      end
    end
  end
end
