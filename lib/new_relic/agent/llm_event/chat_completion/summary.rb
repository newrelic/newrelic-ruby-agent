# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class NewRelic
  class Agent
    class LlmEvent
      class ChatCompletion
        attr_accessor
          :request_model,
          :response_organization,
          :response_usage_total_tokens,
          :response_usage_prompt_tokens,
          :response_usage_completion_tokens,
          :response_choices_finish_reason,
          :response_headers_llmVersion,
          :response_headers_ratelimitLimitRequests,
          :response_headers_ratelimitLimitTokens,
          :response_headers_ratelimitResetTokens,
          :response_headers_ratelimitResetRequests,
          :response_headers_ratelimitRemainingTokens,
          :response_headers_ratelimitRemainingRequests,
          :duration,
          :request_temperature,
          :error

        EVENT_NAME = 'LlmChatCompletionSummary'

        class Summary < NewRelic::Agent::LlmEvent::ChatCompletion
          def initialize (request_model:, response_organization:, response_usage_total_tokens:, response_usage_prompt_tokens:, response_usage_completion_tokens:,
            response_choices_finish_reason:, response_headers_llmVersion:, response_headers_ratelimitLimitRequests:, response_headers_ratelimitLimitTokens:,
            response_headers_ratelimitResetTokens:, response_headers_ratelimitResetRequests:, response_headers_ratelimitRemainingTokens:,
            response_headers_ratelimitRemainingRequests:, duration:, request_temperature:, error:, **args)
            @request_model = request_model
            @response_organization = response_organization
            @response_usage_total_tokens = response_usage_total_tokens
            @response_usage_prompt_tokens = response_usage_prompt_tokens
            @response_usage_completion_tokens = response_usage_completion_tokens
            @response_choices_finish_reason = response_choices_finish_reason
            @response_headers_llmVersion = response_headers_llmVersion
            @response_headers_ratelimitLimitRequests = response_headers_ratelimitLimitRequests
            @response_headers_ratelimitLimitTokens = response_headers_ratelimitLimitTokens
            @response_headers_ratelimitResetTokens = response_headers_ratelimitResetTokens
            @response_headers_ratelimitResetRequests = response_headers_ratelimitResetRequests
            @response_headers_ratelimitRemainingTokens = response_headers_ratelimitRemainingTokens
            @response_headers_ratelimitRemainingRequests = response_headers_ratelimitRemainingRequests
            @duration = duration
            @request_temperature = request_temperature
            @error = error
            super
          end

          def summary_attributes
            {
              request_model: @request_model,
              response_organization: @response_organization,
              response_usage_total_tokens: @response_usage_total_tokens,
              response_usage_prompt_tokens: @response_usage_prompt_tokens,
              response_usage_completion_tokens: @response_usage_completion_tokens,
              response_choices_finish_reason: @response_choices_finish_reason,
              response_headers_llmVersion: @response_headers_llmVersion,
              response_headers_ratelimitLimitRequests: @response_headers_ratelimitLimitRequests,
              response_headers_ratelimitLimitTokens: @response_headers_ratelimitLimitTokens,
              response_headers_ratelimitResetTokens: @response_headers_ratelimitResetTokens,
              response_headers_ratelimitResetRequests: @response_headers_ratelimitResetRequests,
              response_headers_ratelimitRemainingTokens: @response_headers_ratelimitRemainingTokens,
              response_headers_ratelimitRemainingRequests: @response_headers_ratelimitRemainingRequests,
              duration: @duration,
              request_temperature: @request_temperature,
              error: @error
            }.merge(chat_completion_attributes, llm_event_attributes)
          end

          def record
            NewRelic::Agent.record_custom_event(EVENT_NAME, summary_attributes)
          end
        end
      end
    end
  end
end