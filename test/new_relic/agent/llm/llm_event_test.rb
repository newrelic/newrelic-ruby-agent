# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'

module NewRelic::Agent::Llm
  class LlmEventTest < Minitest::Test
    def test_agent_defined_attributes_set
      assert_includes NewRelic::Agent::Llm::LlmEvent::AGENT_DEFINED_ATTRIBUTES, :transaction_id

      in_transaction do |txn|
        event = NewRelic::Agent::Llm::LlmEvent.new(transaction_id: 'fake')

        refute_equal 'fake', event.transaction_id
        assert_equal txn.guid, event.transaction_id
      end
    end

    def test_attributes_constant_values_can_be_passed_as_args_and_set_on_init
      id = 123
      event = NewRelic::Agent::Llm::LlmEvent.new(id: id)

      assert_equal id, event.id
    end

    def test_args_passed_to_init_not_set_as_instance_vars_when_not_in_attributes_constant
      event = NewRelic::Agent::Llm::LlmEvent.new(fake: 'fake')

      refute event.instance_variable_defined?(:@fake)
    end

    def test_event_attributes_returns_a_hash_of_assigned_attributes_and_values
      event = NewRelic::Agent::Llm::LlmEvent.new(id: 123)
      event.vendor = 'OpenAI'
      event.response_model = 'gpt-4'
      result = event.event_attributes

      assert_instance_of(Hash, result)
      assert_equal(123, result[:id])
      assert_equal('OpenAI', result[:vendor])
      assert_equal('gpt-4', result['response.model'])
    end

    def test_record_does_not_create_an_event
      event = NewRelic::Agent::Llm::LlmEvent.new
      event.record
      _, events = NewRelic::Agent.agent.custom_event_aggregator.harvest!

      assert_empty events
    end

    def test_initialize_sets_id_as_guid_if_no_arg_passed
      NewRelic::Agent::GuidGenerator.stub(:generate_guid, 123) do
        event = NewRelic::Agent::Llm::LlmEvent.new

        assert_equal 123, event.id
      end
    end

    def test_initialize_sets_id_as_arg_if_passed
      id = 456
      event = NewRelic::Agent::Llm::LlmEvent.new(id: id)

      assert_equal(id, event.id)
    end

    def test_set_llm_agent_attribute_on_transaction
      in_transaction do |txn|
        NewRelic::Agent::Llm::LlmEvent.set_llm_agent_attribute_on_transaction
        NewRelic::Agent.notice_error(NewRelic::TestHelpers::Exceptions::TestError.new)
      end

      assert_truthy harvest_transaction_events![1][0][2][:llm]
      assert_truthy harvest_error_events![1][0][2][:llm]
    end
  end
end
