# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'

module NewRelic::Agent::Llm
  class ChatCompletionSummaryTest < Minitest::Test
    def test_attributes_assigned_by_parent_present
      assert_includes NewRelic::Agent::Llm::ChatCompletionSummary.ancestors, NewRelic::Agent::Llm::LlmEvent
      assert_includes NewRelic::Agent::Llm::LlmEvent::AGENT_DEFINED_ATTRIBUTES, :transaction_id

      in_transaction do |txn|
        event = NewRelic::Agent::Llm::ChatCompletionSummary.new

        assert_equal txn.guid, event.transaction_id
      end
    end

    def test_attributes_in_parent_list_can_be_assigned_on_init
      assert_includes NewRelic::Agent::Llm::LlmEvent::ATTRIBUTES, :id

      event = NewRelic::Agent::Llm::ChatCompletionSummary.new(id: 123)

      assert_equal 123, event.id
    end

    def test_included_module_attributes_list_can_be_assigned_on_init
      assert_includes NewRelic::Agent::Llm::ChatCompletionSummary.ancestors, NewRelic::Agent::Llm::ChatCompletion
      assert_includes NewRelic::Agent::Llm::ChatCompletion::ATTRIBUTES, :conversation_id

      conversation_id = '123abc'
      event = NewRelic::Agent::Llm::ChatCompletionSummary.new(conversation_id: conversation_id)

      assert_equal conversation_id, event.conversation_id
    end

    def test_attributes_constant_values_can_be_passed_as_args_and_set_on_init
      assert_includes NewRelic::Agent::Llm::ChatCompletionSummary::ATTRIBUTES, :request_model
      request_model = 'gpt-4-turbo-preview'
      event = NewRelic::Agent::Llm::ChatCompletionSummary.new(request_model: request_model)

      assert_equal request_model, event.request_model
    end

    def test_args_passed_to_init_not_set_as_instance_vars_when_not_in_attributes_constant
      event = NewRelic::Agent::Llm::ChatCompletionSummary.new(fake: 'fake')

      refute_includes event.attributes, :fake
      refute event.instance_variable_defined?(:@fake)
    end

    def test_record_creates_an_event
      in_transaction do |txn|
        summary = NewRelic::Agent::Llm::ChatCompletionSummary.new(
          id: 123,
          request_model: 'gpt-4-turbo-preview',
          api_key_last_four_digits: 'sk-0713'
        )
        summary.request_id = '789'
        summary.conversation_id = 456
        summary.response_usage_total_tokens = 20
        summary.request_max_tokens = 500
        summary.response_number_of_messages = 5
        summary.request_model = 'gpt-4-turbo-preview'
        summary.response_model = 'gpt-4'
        summary.response_organization = '98338'
        summary.response_usage_total_tokens = 20
        summary.response_usage_prompt_tokens = '24'
        summary.response_usage_completion_tokens = '26'
        summary.response_choices_finish_reason = 'stop'
        summary.vendor = 'OpenAI'
        summary.duration = '500'
        summary.error = 'true'
        summary.llm_version = '2022-01-01'
        summary.rate_limit_requests = '100'
        summary.rate_limit_tokens = '101'
        summary.rate_limit_reset_tokens = '102'
        summary.rate_limit_reset_requests = '103'
        summary.rate_limit_remaining_tokens = '104'
        summary.rate_limit_remaining_requests = '105'

        summary.record
        _, events = NewRelic::Agent.agent.custom_event_aggregator.harvest!
        type, attributes = events[0]

        assert_equal 'LlmChatCompletionSummary', type['type']

        assert_equal 123, attributes['id']
        assert_equal 456, attributes['conversation_id']
        assert_equal '789', attributes['request_id']
        assert_equal txn.current_segment.guid, attributes['span_id']
        assert_equal txn.guid, attributes['transaction_id']
        assert_equal txn.trace_id, attributes['trace_id']
        assert_equal 'sk-0713', attributes['api_key_last_four_digits']
        assert_equal 500, attributes['request_max_tokens']
        assert_equal 5, attributes['response_number_of_messages']
        assert_equal 'gpt-4-turbo-preview', attributes['request_model']
        assert_equal 'gpt-4', attributes['response_model']
        assert_equal '98338', attributes['response_organization']
        assert_equal 20, attributes['response_usage_total_tokens']
        assert_equal '24', attributes['response_usage_prompt_tokens']
        assert_equal '26', attributes['response_usage_completion_tokens']
        assert_equal 'stop', attributes['response_choices_finish_reason']
        assert_equal 'OpenAI', attributes['vendor']
        assert_equal 'Ruby', attributes['ingest_source']
        assert_equal '500', attributes['duration']
        assert_equal 'true', attributes['error']
        assert_equal '2022-01-01', attributes['llm_version']
        assert_equal '100', attributes['rate_limit_requests']
        assert_equal '101', attributes['rate_limit_tokens']
        assert_equal '102', attributes['rate_limit_reset_tokens']
        assert_equal '103', attributes['rate_limit_reset_requests']
        assert_equal '104', attributes['rate_limit_remaining_tokens']
        assert_equal '105', attributes['rate_limit_remaining_requests']
      end
    end
  end
end
