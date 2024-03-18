# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'

module NewRelic::Agent::Llm
  class EmbeddingTest < Minitest::Test
    def setup
      NewRelic::Agent.drop_buffered_data
    end

    def test_attributes_assigned_by_parent_present
      assert_includes NewRelic::Agent::Llm::Embedding.ancestors, NewRelic::Agent::Llm::LlmEvent
      assert_includes NewRelic::Agent::Llm::LlmEvent::AGENT_DEFINED_ATTRIBUTES, :trace_id

      in_transaction do |txn|
        event = NewRelic::Agent::Llm::Embedding.new

        assert_equal txn.trace_id, event.trace_id
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
        embedding.response_model = 'text-embedding-3-large'
        embedding.response_organization = 'newrelic-org-abc123'
        embedding.vendor = 'OpenAI'
        embedding.duration = '500'
        embedding.error = 'true'
        embedding.token_count = 10
        embedding.llm_version = '2022-01-01'
        embedding.ratelimit_limit_requests = 200
        embedding.ratelimit_limit_tokens = 40000
        embedding.ratelimit_reset_tokens = '180ms'
        embedding.ratelimit_reset_requests = '11m32.334s'
        embedding.ratelimit_remaining_tokens = 39880
        embedding.ratelimit_remaining_requests = 198
        embedding.ratelimit_limit_tokens_usage_based = 40000
        embedding.ratelimit_reset_tokens_usage_based = '180ms'
        embedding.ratelimit_remaining_tokens_usage_based = 39880

        embedding.record
        _, events = NewRelic::Agent.agent.custom_event_aggregator.harvest!
        type, attributes = events[0]

        assert_equal 'LlmEmbedding', type['type']

        assert_equal 123, attributes['id']
        assert_equal '789', attributes['request_id']
        assert_equal txn.current_segment.guid, attributes['span_id']
        assert_equal txn.trace_id, attributes['trace_id']
        assert_equal 'Bonjour', attributes['input']
        assert_equal 'text-embedding-ada-002', attributes['request.model']
        assert_equal 'text-embedding-3-large', attributes['response.model']
        assert_equal 'newrelic-org-abc123', attributes['response.organization']
        assert_equal 'OpenAI', attributes['vendor']
        assert_equal 'Ruby', attributes['ingest_source']
        assert_equal '500', attributes['duration']
        assert_equal 'true', attributes['error']
        assert_equal 10, attributes['token_count']
        assert_equal '2022-01-01', attributes['response.headers.llmVersion']
        assert_equal 200, attributes['response.headers.ratelimitLimitRequests']
        assert_equal 40000, attributes['response.headers.ratelimitLimitTokens']
        assert_equal '180ms', attributes['response.headers.ratelimitResetTokens']
        assert_equal '11m32.334s', attributes['response.headers.ratelimitResetRequests']
        assert_equal 39880, attributes['response.headers.ratelimitRemainingTokens']
        assert_equal 198, attributes['response.headers.ratelimitRemainingRequests']
        assert_equal 40000, attributes['response.headers.ratelimitLimitTokensUsageBased']
        assert_equal '180ms', attributes['response.headers.ratelimitResetTokensUsageBased']
        assert_equal 39880, attributes['response.headers.ratelimitRemainingTokensUsageBased']
      end
    end

    def test_error_attributes
      event = NewRelic::Agent::Llm::Embedding.new
      expected =
        {
          'http.statusCode' => 400,
          'error.code' => nil,
          'error.param' => nil,
          'embedding_id' => event.id
        }
      exception = MockFaradayBadResponseError.new

      assert_equal expected, event.error_attributes(exception)
    end

    def test_error_attributes_for_irregular_exception
      event = NewRelic::Agent::Llm::Embedding.new
      expected = {'embedding_id' => event.id}
      exception = StandardError.new

      assert_equal expected, event.error_attributes(exception)
    end

    class MockFaradayBadResponseError
      # Return value from an OpenAI embeddings request without a model parameter
      # Recorded 21 Feb 2024
      def response
        {
          :status => 400,
          :headers =>
          {'date' => 'Wed, 21 Feb 2024 23:50:19 GMT',
           'content-type' => 'application/json; charset=utf-8',
           'content-length' => '167',
           'connection' => 'keep-alive',
           'vary' => 'Origin',
           'x-request-id' => 'req_e123',
           'strict-transport-security' => 'max-age=15724800; includeSubDomains',
           'cf-cache-status' => 'DYNAMIC',
           'set-cookie' => 'unused',
           'server' => 'cloudflare',
           'cf-ray' => 'unused',
           'alt-svc' => 'unused'},
          :body =>
          {'error' =>
            {'message' => 'you must provide a model parameter',
             'type' => 'invalid_request_error',
             'param' => nil,
             'code' => nil}},
          :request =>
          {:method => :post,
           :url => '#<URI::HTTPS https://api.openai.com/v1/embeddings>', # this is an instance of a class, not a string, in the real response
           :url_path => '/v1/embeddings',
           :params => nil,
           :headers =>
            {'Content-Type' => 'application/json',
             'Authorization' => 'Bearer sk-123',
             'OpenAI-Organization' => nil},
           :body => '{"input":"The food was delicious and the waiter..."}'}
        }
      end
    end
  end
end
