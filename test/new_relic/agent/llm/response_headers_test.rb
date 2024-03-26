# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'

module NewRelic::Agent::Llm
  class ResponseHeadersTest < Minitest::Test
    def setup
      NewRelic::Agent.drop_buffered_data
    end

    def openai_response_headers_hash
      # Response headers from a real OpenAI request
      # rubocop:disable Style/StringLiterals, Style/WordArray
      {"date" => ["Thu, 25 Jan 2024 23:16:44 GMT"],
       "content-type" => ["application/json"],
       "transfer-encoding" => ["chunked"],
       "connection" => ["keep-alive"],
       "access-control-allow-origin" => ["*"],
       "openai-model" => ["text-embedding-ada-002"],
       "openai-organization" =>
      ["user-whatever"],
       "openai-processing-ms" => ["22"],
       "openai-version" => ["2020-10-01"],
       "strict-transport-security" =>
      ["max-age=15724800; includeSubDomains"],
       "x-ratelimit-limit-requests" => ["200"],
       "x-ratelimit-limit-tokens" => ["150000"],
       "x-ratelimit-remaining-requests" => ["199"],
       "x-ratelimit-remaining-tokens" => ["149990"],
       "x-ratelimit-reset-requests" => ["7m12s"],
       "x-ratelimit-reset-tokens" => ["4ms"],
       # The following *-tokens-usage-based entries are best guesses to fulfill the spec. We haven't been able to create a request that returns these headers.
       "x-ratelimit-limit-tokens-usage-based" => ["40000"],
       "x-ratelimit-reset-tokens-usage-based" => ["180ms"],
       "x-ratelimit-remaining-tokens-usage-based" => ["39880"],
       "x-request-id" => ["123abc456"],
       "cf-cache-status" => ["DYNAMIC"],
       "set-cookie" =>
      ["we-dont-use-this-value",
        "we-dont-use-this-value"],
       "server" => ["cloudflare"],
       "cf-ray" => ["123abc-SJC"],
       "alt-svc" => ["h3=\":443\"; ma=86400"]}
      # rubocop:enable Style/StringLiterals, Style/WordArray
    end

    def test_populate_openai_response_headers
      event = NewRelic::Agent::Llm::ChatCompletionSummary.new
      event.populate_openai_response_headers(openai_response_headers_hash)

      assert_equal '2020-10-01', event.llm_version
      assert_equal 200, event.ratelimit_limit_requests
      assert_equal 150000, event.ratelimit_limit_tokens
      assert_equal 199, event.ratelimit_remaining_requests
      assert_equal 149990, event.ratelimit_remaining_tokens
      assert_equal '7m12s', event.ratelimit_reset_requests
      assert_equal '4ms', event.ratelimit_reset_tokens
      assert_equal 40000, event.ratelimit_limit_tokens_usage_based
      assert_equal '180ms', event.ratelimit_reset_tokens_usage_based
      assert_equal 39880, event.ratelimit_remaining_tokens_usage_based
    end
  end
end
