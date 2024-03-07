# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module OpenAIHelpers
  class ChatResponse
    def body(return_value: false)
      if Gem::Version.new(::OpenAI::VERSION) >= Gem::Version.new('6.0.0') || return_value
        {'id' => 'chatcmpl-8nEZg6Gb5WFOwAz34Hivh4IXH0GHq',
         'object' => 'chat.completion',
         'created' => 1706744788,
         'model' => 'gpt-3.5-turbo-0613',
         'choices' =>
          [{'index' => 0,
            'message' => {'role' => 'assistant', 'content' => 'The 2020 World Series was played at Globe'},
            'logprobs' => nil,
            'finish_reason' => 'length'}],
         'usage' => {'prompt_tokens' => 53, 'completion_tokens' => 10, 'total_tokens' => 63},
         'system_fingerprint' => nil}
      else
        "{\n  \"id\": \"chatcmpl-8nEZg6Gb5WFOwAz34Hivh4IXH0GHq\",\n  \"object\": \"chat.completion\",\n  \"created\": 1706744788,\n  \"model\": \"gpt-3.5-turbo-0613\",\n  \"choices\": [\n    {\n      \"index\": 0,\n      \"message\": {\n        \"role\": \"assistant\",\n        \"content\": \"The 2020 World Series was played at Globe\"\n      },\n      \"logprobs\": null,\n      \"finish_reason\": \"length\"\n    }\n  ],\n  \"usage\": {\n    \"prompt_tokens\": 53,\n    \"completion_tokens\": 10,\n    \"total_tokens\": 63\n  },\n  \"system_fingerprint\": null\n}\n"
      end
    end

    def error_response(return_value: false)
      if Gem::Version.new(::OpenAI::VERSION) >= Gem::Version.new('4.3.2') || return_value
        nil
      else
        {'error' => {'message' => 'you must provide a model parameter', 'type' => 'invalid_request_error', 'param' => nil, 'code' => nil}}
      end
    end
  end

  class EmbeddingsResponse
    def body(return_value: false)
      {'object' => 'list',
       'data' => [{
         'object' => 'embedding',
         'index' => 0,
         'embedding' => [0.002297497, 1, -0.016932933, 0.018126108, -0.014432343, -0.0030051514] # A real embeddings response includes dozens more vector points.
       }],
       'model' => 'text-embedding-ada-002',
       'usage' => {'prompt_tokens' => 8, 'total_tokens' => 8}}
    end
  end

  def client
    @client ||= OpenAI::Client.new(access_token: 'FAKE_ACCESS_TOKEN')
  end

  def connection_client
    Gem::Version.new(::OpenAI::VERSION) <= Gem::Version.new('4.3.2') ? OpenAI::Client : client
  end

  def embeddings_params
    {
      model: 'text-embedding-ada-002',
      input: 'The food was delicious and the waiter...'
    }
  end

  def missing_embeddings_param
    {
      input: 'The food was delicious and the waiter...'
    }
  end

  def chat_params
    {
      model: 'gpt-3.5-turbo',
      messages: [
        {'role' => 'system', 'content': 'You are a helpful assistant.'},
        {'role': 'user', 'content' => 'Who won the world series in 2020?'},
        {'role': 'assistant', 'content': 'The Los Angeles Dodgers won the World Series in 2020.'},
        {'role': 'user', 'content': 'Where was it played?'}
      ],
      temperature: 0.7,
      max_tokens: 10
    }
  end

  def chat_completion_net_http_response_headers
    {'date' => ['Fri, 02 Feb 2024 17:37:16 GMT'],
     'content-type' => ['application/json'],
     'transfer-encoding' => ['chunked'],
     'connection' => ['keep-alive'],
     'access-control-allow-origin' => ['*'],
     'cache-control' => ['no-cache, must-revalidate'],
     'openai-model' => ['gpt-3.5-turbo-0613'],
     'openai-organization' => ['user-gr8l0l'],
     'openai-processing-ms' => ['242'],
     'openai-version' => ['2020-10-01'],
     'strict-transport-security' => ['max-age=15724800; includeSubDomains'],
     'x-ratelimit-limit-requests' => ['5000'],
     'x-ratelimit-limit-tokens' => ['80000'],
     'x-ratelimit-remaining-requests' => ['4999'],
     'x-ratelimit-remaining-tokens' => ['79952'],
     'x-ratelimit-reset-requests' => ['12ms'],
     'x-ratelimit-reset-tokens' => ['36ms'],
     'x-request-id' => ['cabbag3'],
     'cf-cache-status' => ['DYNAMIC'],
     'set-cookie' =>
  ['__cf_bm=8fake_value; path=/; expires=Fri, 02-Feb-24 18:07:16 GMT; domain=.api.openai.com; HttpOnly; Secure; SameSite=None',
    '_cfuvid=fake_value; path=/; domain=.api.openai.com; HttpOnly; Secure; SameSite=None'],
     'server' => ['cloudflare'],
     'cf-ray' => ['g2g-SJC'],
     'alt-svc' => ['h3=":443"; ma=86400']}
  end

  def edits_params
    {
      model: 'text-davinci-edit-001',
      input: 'What day of the wek is it?',
      instruction: 'Fix the spelling mistakes'
    }
  end

  # ruby-openai uses HTTP clients (Faraday, HTTParty) to make requests to the
  # OpenAI API. By stubbing the connection, we avoid making HTTP requests.
  def faraday_connection
    faraday_connection = Faraday.new
    def faraday_connection.post(*args); ChatResponse.new; end

    faraday_connection
  end

  def error_faraday_connection
    faraday_connection = Faraday.new
    def faraday_connection.post(*args); raise 'deception'; end

    faraday_connection
  end

  def error_httparty_connection
    def HTTParty.post(*args); raise 'deception'; end
  end

  def simulate_error(&blk)
    if Gem::Version.new(::OpenAI::VERSION) < Gem::Version.new('4.0.0')
      error_httparty_connection
      yield
    else
      connection_client.stub(:conn, error_faraday_connection) do
        yield
      end
    end
  end

  def embedding_segment(txn)
    txn.segments.find { |s| s.name == 'Llm/embedding/OpenAI/embeddings' }
  end

  def chat_completion_segment(txn)
    txn.segments.find { |s| s.name == 'Llm/completion/OpenAI/chat' }
  end

  def raise_segment_error(&blk)
    txn = nil

    begin
      in_transaction('OpenAI') do |ai_txn|
        txn = ai_txn
        simulate_error do
          yield
        end
      end
    rescue StandardError
      # NOOP - allow span and transaction to notice error
    end

    txn
  end

  def stub_post_request(&blk)
    if Gem::Version.new(::OpenAI::VERSION) <= Gem::Version.new('3.4.0')
      HTTParty.stub(:post, ChatResponse.new.body(return_value: true)) do
        yield
      end
    else
      connection_client.stub(:conn, faraday_connection) do
        yield
      end
    end
  end

  def stub_error_post_request(&blk)
    if Gem::Version.new(::OpenAI::VERSION) <= Gem::Version.new('3.4.0')
      HTTParty.stub(:post, ChatResponse.new.error_response(return_value: true)) do
        yield
      end
    else
      connection_client.stub(:conn, faraday_connection) do
        yield
      end
    end
  end

  def stub_embeddings_post_request(&blk)
    if Gem::Version.new(::OpenAI::VERSION) <= Gem::Version.new('3.4.0')
      HTTParty.stub(:post, EmbeddingsResponse.new.body(return_value: true)) do
        yield
      end
    else
      connection_client.stub(:conn, faraday_connection) do
        yield
      end
    end
  end
end
