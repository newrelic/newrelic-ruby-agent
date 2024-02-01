# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module OpenAIHelpers
  def client
    @client ||= OpenAI::Client.new(access_token: 'FAKE_ACCESS_TOKEN')
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

  # ruby-openai uses Faraday to make requests to the OpenAI API
  # by stubbing the connection, we can avoid making HTTP requests
  def faraday_connection
    faraday_connection = Faraday.new
    def faraday_connection.post(*args); ChatResponse.new; end

    faraday_connection
  end

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
end
