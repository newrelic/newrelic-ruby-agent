# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'

module NewRelic::Agent::Llm
  class ChatCompletionSummaryTest < Minitest::Test
    def setup
      NewRelic::Agent.drop_buffered_data
    end

    def test_attributes_assigned_by_parent_present
      assert_includes NewRelic::Agent::Llm::ChatCompletionSummary.ancestors, NewRelic::Agent::Llm::LlmEvent
      assert_includes NewRelic::Agent::Llm::LlmEvent::AGENT_DEFINED_ATTRIBUTES, :trace_id

      in_transaction do |txn|
        event = NewRelic::Agent::Llm::ChatCompletionSummary.new

        assert_equal txn.trace_id, event.trace_id
      end
    end

    def test_attributes_in_parent_list_can_be_assigned_on_init
      assert_includes NewRelic::Agent::Llm::LlmEvent::ATTRIBUTES, :id

      event = NewRelic::Agent::Llm::ChatCompletionSummary.new(id: 123)

      assert_equal 123, event.id
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
          request_model: 'gpt-4-turbo-preview'
        )
        summary.request_id = '789'
        summary.response_usage_total_tokens = 20
        summary.request_temperature = 0.7
        summary.request_max_tokens = 500
        summary.request_model = 'gpt-4-turbo-preview'
        summary.response_model = 'gpt-4'
        summary.response_organization = 'newrelic-org-abc123'
        summary.response_number_of_messages = 5
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
        assert_equal '789', attributes['request_id']
        assert_equal txn.current_segment.guid, attributes['span_id']
        assert_equal txn.trace_id, attributes['trace_id']
        assert_equal 0.7, attributes['request.temperature'] # rubocop:disable Minitest/AssertInDelta
        assert_equal 500, attributes['request_max_tokens']
        assert_equal 5, attributes['response.number_of_messages']
        assert_equal 'gpt-4-turbo-preview', attributes['request.model']
        assert_equal 'gpt-4', attributes['response.model']
        assert_equal 'newrelic-org-abc123', attributes['response.organization']
        assert_equal 20, attributes['response.usage.total_tokens']
        assert_equal '24', attributes['response.usage.prompt_tokens']
        assert_equal '26', attributes['response.usage.completion_tokens']
        assert_equal 'stop', attributes['response.choices.finish_reason']
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

    def test_error_attributes
      event = NewRelic::Agent::Llm::ChatCompletionSummary.new
      expected =
        {
          'http.statusCode' => 400,
          'error.code' => nil,
          'error.param' => nil,
          'completion_id' => event.id
        }
      exception = MockFaradayBadResponseError.new

      assert_equal expected, event.error_attributes(exception)
    end

    def test_error_attributes_for_irregular_exception
      event = NewRelic::Agent::Llm::ChatCompletionSummary.new
      expected = {'completion_id' => event.id}
      exception = StandardError.new

      assert_equal expected, event.error_attributes(exception)
    end

    class MockFaradayBadResponseError < StandardError
      # Return value from an OpenAI chat completions request without a model parameter
      # Recorded 21 Feb 2024
      def response
        {
          :status => 400,
          :headers =>
            {'date' => 'Wed, 21 Feb 2024 23:52:49 GMT',
             'content-type' => 'application/json; charset=utf-8',
             'content-length' => '167',
             'connection' => 'keep-alive',
             'vary' => 'Origin',
             'x-request-id' => 'req_123',
             'strict-transport-security' => 'max-age=15724800; includeSubDomains',
             'cf-cache-status' => 'DYNAMIC',
             'set-cookie' =>
            'unused',
             'server' => 'cloudflare',
             'cf-ray' => '8592e7bafe24c4b6-SEA',
             'alt-svc' => 'h3=":443"; ma=86400'},
          :body =>
          {'error' =>
            {'message' => 'you must provide a model parameter',
             'type' => 'invalid_request_error',
             'param' => nil,
             'code' => nil}},
          :request =>
          {:method => :post,
           :url => '#<URI::HTTPS https://api.openai.com/v1/chat/completions>', # this is an instance of a class, not a string, in the real response
           :url_path => '/v1/chat/completions',
           :params => nil,
           :headers =>
            {'Content-Type' => 'application/json',
             'Authorization' => 'Bearer sk-123',
             'OpenAI-Organization' => nil},
           :body =>
            '{"messages":[{"role":"system","content":"You are a helpful assistant."},{"role":"user","content":"Who won the world series in 2020?"},{"role":"assistant","content":"The Los Angeles Dodgers won the World Series in 2020."},{"role":"user","content":"Where was it played?"}],"temperature":0.7}'}
        }
      end
    end
  end
end
