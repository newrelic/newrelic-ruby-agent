# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'response_headers'

module NewRelic
  module Agent
    module Llm
      class ChatCompletionSummary < LlmEvent
        include ChatCompletion
        include ResponseHeaders

        ATTRIBUTES = %i[api_key_last_four_digits request_max_tokens
          response_number_of_messages request_model response_usage_total_tokens response_usage_prompt_tokens response_usage_completion_tokens response_choices_finish_reason
          request_temperature duration error]
        ATTRIBUTE_NAME_EXCEPTIONS = {
          response_number_of_messages: 'response.number_of_messages',
          request_model: 'request.model',
          response_usage_total_tokens: 'response.usage.total_tokens',
          response_usage_prompt_tokens: 'response.usage.prompt_tokens',
          response_usage_completion_tokens: 'response.usage.completion_tokens',
          response_choices_finish_reason: 'response.choices.finish_reason',
          temperature: 'request.temperature'
        }

        EVENT_NAME = 'LlmChatCompletionSummary'

        attr_accessor(*ATTRIBUTES)

        def attributes
          LlmEvent::ATTRIBUTES + ChatCompletion::ATTRIBUTES + ResponseHeaders::ATTRIBUTES + ATTRIBUTES
        end

        def attribute_name_exceptions
          # TODO: OLD RUBIES < 2.6
          # Hash#merge accepts multiple arguments in 2.6
          # Remove condition once support for Ruby <2.6 is dropped
          if RUBY_VERSION >= '2.6.0'
            LlmEvent::ATTRIBUTE_NAME_EXCEPTIONS.merge(ResponseHeaders::ATTRIBUTE_NAME_EXCEPTIONS, ATTRIBUTE_NAME_EXCEPTIONS)
          else
            LlmEvent::ATTRIBUTE_NAME_EXCEPTIONS.merge(ResponseHeaders::ATTRIBUTE_NAME_EXCEPTIONS).merge(ATTRIBUTE_NAME_EXCEPTIONS)
          end
        end

        def event_name
          EVENT_NAME
        end
      end
    end
  end
end
