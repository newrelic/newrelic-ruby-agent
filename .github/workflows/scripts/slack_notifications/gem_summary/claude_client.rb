# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'httparty'
require 'json'

module GemSummary
  class ClaudeClient
    MODEL = 'claude-4-7-opus'
    MAX_TOKENS = 1000
    MAX_RETRIES = 1

    def initialize
      @api_key = ENV['ANTHROPIC_API_KEY']
      @api_endpoint = ENV['CLAUDE_API_ENDPOINT']
    end

    def send_message(prompt)
      if @api_key.to_s.empty? || @api_endpoint.to_s.empty?
        puts 'Warning: Claude API skipped — ANTHROPIC_API_KEY or CLAUDE_API_ENDPOINT not set'
        return nil
      end

      retries = 0
      begin
        response = HTTParty.post(
          @api_endpoint,
          headers: {
            'Content-Type' => 'application/json',
            'Authorization' => "Bearer #{@api_key}"
          },
          body: {
            model: MODEL,
            max_tokens: MAX_TOKENS,
            messages: [{role: 'user', content: prompt}]
          }.to_json,
          timeout: 30
        )

        status = response.code
        return nil unless status == 200

        JSON.parse(response.body).dig('content', 0, 'text')
      rescue StandardError => e
        retries += 1
        if retries <= MAX_RETRIES
          puts "Warning: Claude API error (attempt #{retries}): #{e.message}. Retrying..."
          sleep(1)
          retry
        end
        puts "Warning: Claude API error: #{e.message}"
        nil
      end
    end
  end
end
