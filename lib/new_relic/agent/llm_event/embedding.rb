# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class NewRelic
  class Agent
    class LlmEvent
      class Embedding < NewRelic::Agent::LlmEvent

        # The real object for all response_ actially is response.x.
        attr_accessor
          :input,
          :request_model,
          :response_organization,
          :response_usage_total_tokens,
          :response_usage_prompt_tokens,
          :response_headers_llmVersion,
          :response_headers_ratelimitLimitRequests
          :response_headers_ratelimitLimitTokens,
          :response_headers_ratelimitResetTokens,
          :response_headers_ratelimitResetRequests,
          :response_headers_ratelimitRemainingTokens,
          :response_headers_ratelimitRemainingRequests,
          :duration,
          :error

          EVENT_NAME = 'LlmEmbedding'

        def initialize (input:, request_model:, response_organization:, response_usage_total_tokens:, response_usage_prompt_tokens:, response_headers_llmVersion:,
          response_headers_ratelimitLimitRequests:, response_headers_ratelimitLimitTokens:, response_headers_ratelimitResetTokens:, response_headers_ratelimitResetRequests:,
          response_headers_ratelimitRemainingTokens:, response_headers_ratelimitRemainingRequests:, duration:, error:, **args)
          @input = input
          @request_model = request_model
          @response_organization = response_organization
          @response_usage_total_tokens = response_usage_total_tokens
          @response_usage_prompt_tokens = response_usage_prompt_tokens
          @response_headers_llmVersion = response_headers_llmVersion
          @response_headers_ratelimitLimitRequests = response_headers_ratelimitLimitRequests
          @response_headers_ratelimitLimitTokens = response_headers_ratelimitLimitTokens
          @response_headers_ratelimitResetTokens = response_headers_ratelimitResetTokens
          @response_headers_ratelimitResetRequests = response_headers_ratelimitResetRequests
          @response_headers_ratelimitRemainingTokens = response_headers_ratelimitRemainingTokens
          @response_headers_ratelimitRemainingRequests = response_headers_ratelimitRemainingRequests
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
            response_headers_llmVersion: @response_headers_llmVersion,
            response_headers_ratelimitLimitRequests: @response_headers_ratelimitLimitRequests,
            response_headers_ratelimitLimitTokens: @response_headers_ratelimitLimitTokens,
            response_headers_ratelimitResetTokens: @response_headers_ratelimitResetTokens,
            response_headers_ratelimitResetRequests: @response_headers_ratelimitResetRequests,
            response_headers_ratelimitRemainingTokens: @response_headers_ratelimitRemainingTokens,
            response_headers_ratelimitRemainingRequests: @response_headers_ratelimitRemainingRequests,
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