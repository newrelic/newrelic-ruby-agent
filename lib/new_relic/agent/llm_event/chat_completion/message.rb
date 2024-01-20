# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class LlmEvent
      class ChatCompletion
        class Message < ChatCompletion
          attr_accessor :content, :role, :sequence, :completion_id, :is_response
          EVENT_NAME = 'LlmChatCompletionMessage'

          def initialize(content: nil, role: nil, sequence: nil, completion_id: nil, is_response: nil, **args)
            @content = content
            @role = role
            @sequence = sequence
            @completion_id = completion_id
            @is_response = is_response
            super
          end

          def message_attributes
            {content: @content, role: @role}.merge(chat_completion_attributes, llm_event_attributes)
          end

          def record
            NewRelic::Agent.record_custom_event(EVENT_NAME, message_attributes)
          end
        end
      end
    end
  end
end
