# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class LlmEvent
      class ChatCompletion < LlmEvent
        # TODO: should any of the attrs be required on initialization?
        def initialize(api_key_last_four_digits: nil, conversation_id: nil, request_max_tokens: nil, response_number_of_messages: nil, **args)
          @api_key_last_four_digits = api_key_last_four_digits
          @conversation_id = conversation_id
          @request_max_tokens = request_max_tokens
          @response_number_of_messages = response_number_of_messages
          super
        end

        def chat_completion_attributes
          {api_key_last_four_digits: @api_key_last_four_digits, conversation_id: @conversation_id,
           request_max_tokens: @request_max_tokens, response_number_of_messages: @response_number_of_messages}
        end

        # Method for subclasses to override
        def record; end
      end
    end
  end
end
