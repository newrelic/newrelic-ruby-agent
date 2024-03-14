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
          response_number_of_messages request_model response_organization
          response_usage_total_tokens response_usage_prompt_tokens
          response_usage_completion_tokens response_choices_finish_reason
          request_temperature duration error]
        EVENT_NAME = 'LlmChatCompletionSummary'

        attr_accessor(*ATTRIBUTES)

        def attributes
          LlmEvent::ATTRIBUTES + ChatCompletion::ATTRIBUTES + ResponseHeaders::ATTRIBUTES + ATTRIBUTES
        end

        def event_name
          EVENT_NAME
        end
      end
    end
  end
end
