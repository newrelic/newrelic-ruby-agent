# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'

module NewRelic::Agent::Llm
  class ChatCompletionMessageTest < Minitest::Test
    def setup
      NewRelic::Agent.drop_buffered_data
    end

    def test_attributes_assigned_by_parent_present
      assert_includes NewRelic::Agent::Llm::ChatCompletionMessage.ancestors, NewRelic::Agent::Llm::LlmEvent
      assert_includes NewRelic::Agent::Llm::LlmEvent::AGENT_DEFINED_ATTRIBUTES, :transaction_id

      in_transaction do |txn|
        event = NewRelic::Agent::Llm::ChatCompletionMessage.new

        assert_equal txn.guid, event.transaction_id
      end
    end

    def test_attributes_in_parent_list_can_be_assigned_on_init
      assert_includes NewRelic::Agent::Llm::LlmEvent::ATTRIBUTES, :id

      event = NewRelic::Agent::Llm::ChatCompletionMessage.new(id: 123)

      assert_equal 123, event.id
    end

    def test_attributes_constant_values_can_be_passed_as_args_and_set_on_init
      assert_includes NewRelic::Agent::Llm::ChatCompletionMessage::ATTRIBUTES, :role
      role = 'user'
      event = NewRelic::Agent::Llm::ChatCompletionMessage.new(role: role)

      assert_equal role, event.role
    end

    def test_args_passed_to_init_not_set_as_instance_vars_when_not_in_attributes_constant
      event = NewRelic::Agent::Llm::ChatCompletionMessage.new(fake: 'fake')

      refute_includes event.attributes, :fake
      refute event.instance_variable_defined?(:@fake)
    end

    def test_record_creates_an_event
      in_transaction do |txn|
        message = NewRelic::Agent::Llm::ChatCompletionMessage.new(
          id: 7, content: 'Red-Tailed Hawk'
        )
        message.sequence = 2
        message.request_id = '789'
        message.response_model = 'gpt-4'
        message.vendor = 'OpenAI'
        message.role = 'system'
        message.completion_id = 123
        message.is_response = 'true'

        message.record
        _, events = NewRelic::Agent.agent.custom_event_aggregator.harvest!
        type, attributes = events[0]

        assert_equal 'LlmChatCompletionMessage', type['type']

        assert_equal 7, attributes['id']
        assert_equal '789', attributes['request_id']
        assert_equal txn.current_segment.guid, attributes['span_id']
        assert_equal txn.guid, attributes['transaction_id']
        assert_equal txn.trace_id, attributes['trace_id']
        assert_equal 'gpt-4', attributes['response.model']
        assert_equal 'OpenAI', attributes['vendor']
        assert_equal 'Ruby', attributes['ingest_source']
        assert_equal 'Red-Tailed Hawk', attributes['content']
        assert_equal 'system', attributes['role']
        assert_equal 2, attributes['sequence']
        assert_equal 123, attributes['completion_id']
        assert_equal 'true', attributes['is_response']
      end
    end
  end
end
