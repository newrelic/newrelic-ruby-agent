# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Llm
      class ChatCompletionMessage < LlmEvent
        include ChatCompletion

        ATTRIBUTES = %i[content role sequence completion_id token_count
          is_response]
        EVENT_NAME = 'LlmChatCompletionMessage'

        attr_accessor(*ATTRIBUTES)

        def attributes
          LlmEvent::ATTRIBUTES + ChatCompletion::ATTRIBUTES + ATTRIBUTES
        end

        def event_name
          EVENT_NAME
        end
      end
    end
  end
end
