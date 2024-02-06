# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module OpenAIHelpers
  class ChatResponse
    def body
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
    end
  end

  def client
    @client ||= OpenAI::Client.new(access_token: 'FAKE_ACCESS_TOKEN')
  end

  def embeddings_params
    {
      model: 'text-embedding-ada-002', # Required.
      input: 'The food was delicious and the waiter...'
    }
  end

  def chat_params
    {
      model: 'gpt-3.5-turbo', # Required.
      messages: [ # Required.
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

  # ruby-openai uses Faraday to make requests to the OpenAI API
  # by stubbing the connection, we can avoid making HTTP requests
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

  def simulate_chat_json_post_error
    client.stub(:conn, error_faraday_connection) do
      client.chat(parameters: chat_params)
    end
  end

  def simulate_embedding_json_post_error
    client.stub(:conn, error_faraday_connection) do
      client.embeddings(parameters: embeddings_params)
    end
  end

  def embedding_segment(txn)
    txn.segments.find { |s| s.name == 'Llm/embedding/OpenAI/create' }
  end

  def chat_completion_segment(txn)
    txn.segments.find { |s| s.name == 'Llm/completion/OpenAI/create' }
  end

  def raise_chat_segment_error
    txn = nil

    begin
      in_transaction('OpenAI') do |ai_txn|
        txn = ai_txn
        simulate_chat_json_post_error
      end
    rescue StandardError
      # NOOP - allow span and transaction to notice error
    end

    txn
  end

  def raise_embedding_segment_error
    txn = nil

    begin
      in_transaction('OpenAI') do |ai_txn|
        txn = ai_txn
        simulate_embedding_json_post_error
      end
    rescue StandardError
      # NOOP - allow span and transaction to notice error
    end

    txn
  end
end
