# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Llm
      class Embedding < LlmEvent
        include ResponseHeaders

        ATTRIBUTES = %i[input api_key_last_four_digits request_model
          response_usage_total_tokens response_usage_prompt_tokens duration
          error]
        ATTRIBUTE_NAME_EXCEPTIONS = {
          request_model: 'request.model',
          response_usage_total_tokens: 'response.usage.total_tokens',
          response_usage_prompt_tokens: 'response.usage.prompt_tokens'
        }
        EVENT_NAME = 'LlmEmbedding'

        attr_accessor(*ATTRIBUTES)

        def attributes
          LlmEvent::ATTRIBUTES + ResponseHeaders::ATTRIBUTES + ATTRIBUTES
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
