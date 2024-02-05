# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'

module NewRelic::Agent::Llm
  class EmbeddingTest < Minitest::Test
    def test_attributes_assigned_by_parent_present
      assert_includes NewRelic::Agent::Llm::Embedding.ancestors, NewRelic::Agent::Llm::LlmEvent
      assert_includes NewRelic::Agent::Llm::LlmEvent::AGENT_DEFINED_ATTRIBUTES, :transaction_id

      in_transaction do |txn|
        event = NewRelic::Agent::Llm::Embedding.new

        assert_equal txn.guid, event.transaction_id
      end
    end

    def test_attributes_in_parent_list_can_be_assigned_on_init
      assert_includes NewRelic::Agent::Llm::LlmEvent::ATTRIBUTES, :id

      event = NewRelic::Agent::Llm::Embedding.new(id: 123)

      assert_equal 123, event.id
    end

    def test_attributes_constant_values_can_be_passed_as_args_and_set_on_init
      assert_includes NewRelic::Agent::Llm::Embedding::ATTRIBUTES, :input
      input = 'Salut!'
      event = NewRelic::Agent::Llm::Embedding.new(input: input)

      assert_equal input, event.input
    end

    def test_args_passed_to_init_not_set_as_instance_vars_when_not_in_attributes_constant
      event = NewRelic::Agent::Llm::Embedding.new(fake: 'fake')

      refute_includes event.attributes, :fake
      refute event.instance_variable_defined?(:@fake)
    end

    def test_record_creates_an_event
      in_transaction do |txn|
        embedding = NewRelic::Agent::Llm::Embedding.new(input: 'Bonjour', request_model: 'text-embedding-ada-002', id: 123)
        embedding.request_id = '789'
        embedding.api_key_last_four_digits = 'sk-0126'
        embedding.response_model = 'text-embedding-3-large'
        embedding.response_organization = 'newrelic-org-abc123'
        embedding.response_usage_total_tokens = '20'
        embedding.response_usage_prompt_tokens = '24'
        embedding.vendor = 'OpenAI'
        embedding.duration = '500'
        embedding.error = 'true'
        embedding.llm_version = '2022-01-01'
        embedding.rate_limit_requests = '100'
        embedding.rate_limit_tokens = '101'
        embedding.rate_limit_reset_tokens = '102'
        embedding.rate_limit_reset_requests = '103'
        embedding.rate_limit_remaining_tokens = '104'
        embedding.rate_limit_remaining_requests = '105'

        embedding.record
        _, events = NewRelic::Agent.agent.custom_event_aggregator.harvest!
        type, attributes = events[0]

        assert_equal 'LlmEmbedding', type['type']

        assert_equal 123, attributes['id']
        assert_equal '789', attributes['request_id']
        assert_equal txn.current_segment.guid, attributes['span_id']
        assert_equal txn.guid, attributes['transaction_id']
        assert_equal txn.trace_id, attributes['trace_id']
        assert_equal 'Bonjour', attributes['input']
        assert_equal 'sk-0126', attributes['api_key_last_four_digits']
        assert_equal 'text-embedding-ada-002', attributes['request.model']
        assert_equal 'text-embedding-3-large', attributes['response.model']
        assert_equal 'newrelic-org-abc123', attributes['response.organization']
        assert_equal '20', attributes['response.usage.total_tokens']
        assert_equal '24', attributes['response.usage.prompt_tokens']
        assert_equal 'OpenAI', attributes['vendor']
        assert_equal 'Ruby', attributes['ingest_source']
        assert_equal '500', attributes['duration']
        assert_equal 'true', attributes['error']
        assert_equal '2022-01-01', attributes['response.headers.llm_version']
        assert_equal '100', attributes['response.headers.ratelimitLimitRequests']
        assert_equal '101', attributes['response.headers.ratelimitLimitTokens']
        assert_equal '102', attributes['response.headers.ratelimitResetTokens']
        assert_equal '103', attributes['response.headers.ratelimitResetRequests']
        assert_equal '104', attributes['response.headers.ratelimitRemainingTokens']
        assert_equal '105', attributes['response.headers.ratelimitRemainingRequests']
      end
    end
  end
end
