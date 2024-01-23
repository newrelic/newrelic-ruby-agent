# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class LlmEvent
      class ChatCompletion
        EVENT_NAME = 'LlmChatCompletionSummary'

        class Summary < NewRelic::Agent::LlmEvent::ChatCompletion
          def initialize (request_model: nil, response_organization: nil, response_usage_total_tokens: nil, response_usage_prompt_tokens: nil, response_usage_completion_tokens: nil,
            response_choices_finish_reason: nil, duration: nil, request_temperature: nil, error: nil, **args)
            @request_model = request_model
            @response_organization = response_organization
            @response_usage_total_tokens = response_usage_total_tokens
            @response_usage_prompt_tokens = response_usage_prompt_tokens
            @response_usage_completion_tokens = response_usage_completion_tokens
            @response_choices_finish_reason = response_choices_finish_reason
            @response_headers = LlmEvent::ResponseHeaders.new
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
              response_headers: @response_headers, # need to do something to break this down further... or just treat like another thing to merge
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
