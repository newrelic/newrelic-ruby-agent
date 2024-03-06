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

        ATTRIBUTES = %i[request_max_tokens response_number_of_messages
          request_model response_choices_finish_reason request_temperature
          duration error]
        ATTRIBUTE_NAME_EXCEPTIONS = {
          response_number_of_messages: 'response.number_of_messages',
          request_model: 'request.model',
          response_choices_finish_reason: 'response.choices.finish_reason',
          request_temperature: 'request.temperature'
        }
        ERROR_COMPLETION_ID = 'completion_id'
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

        def error_attributes(exception)
          attrs = {}
          attrs[ERROR_COMPLETION_ID] = id

          error_attributes_from_response(exception, attrs)
        end

        private

        def error_attributes_from_response(exception, attrs)
          return attrs unless exception.respond_to?(:response)

          attrs[ERROR_ATTRIBUTE_STATUS_CODE] = exception.response.dig(:status)
          attrs[ERROR_ATTRIBUTE_CODE] = exception.response.dig(:body, ERROR_STRING, CODE_STRING)
          attrs[ERROR_ATTRIBUTE_PARAM] = exception.response.dig(:body, ERROR_STRING, PARAM_STRING)

          attrs
        end
      end
    end
  end
end
