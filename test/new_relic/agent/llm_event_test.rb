# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../../agent_helper'

module NewRelic::Agent
  class LlmEventTest < Minitest::Test
    def test_attribute_merge
      message = chat_message
      message.record
      _, events = NewRelic::Agent.agent.custom_event_aggregator.harvest!
      timestamp = events[0][0]['timestamp']
      priority = events[0][0]['priority']

      assert_equal([[
        {'type' => 'LlmChatCompletionMessage',
         'timestamp' => timestamp,
         'priority' => priority},
        {'content' => 'hi',
         'role' => 'speaker',
         'api_key_last_four_digits' => 'sk-0',
         'conversation_id' => 123,
         'request_max_tokens' => 10,
         'response_number_of_messages' => 5,
         'id' => 345,
         'app_name.0' => 'a',
         'app_name.1' => 'b',
         'app_name.2' => 'c'}
      ]], events)
    end

    def chat_message
      NewRelic::Agent::LlmEvent::ChatCompletion::Message.new(
        content: 'hi',
        role: 'speaker',
        api_key_last_four_digits: 'sk-0',
        conversation_id: 123, id: 345,
        app_name: NewRelic::Agent.config[:app_name],
        request_max_tokens: 10,
        response_number_of_messages: 5
      )
    end
  end
end
