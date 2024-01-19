# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true


module NewRelic
  module Agent
    class LlmEvent
      class ChatCompletion < NewRelic::Agent::LlmEvent

        # Real metrics are written: request.max_tokens, response.number_of_messages
        attr_accessor :api_key_last_four_digits, :conversation_id, :request_max_tokens, :response_number_of_messages

        def initialize(api_key_last_four_digits:, conversation_id:, request_max_tokens:, response_number_of_messages:)
          @api_key_last_four_digits = api_key_last_four_digits
          @conversation_id = conversation_id
          @request_max_tokens = request_max_tokens
          @response_number_of_messages = response_number_of_messages
          super
        end

      # Method for subclasses to override
      def record; end
      end
    end
  end
end

