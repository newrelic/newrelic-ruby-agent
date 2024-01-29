# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'

module NewRelic::Agent::Llm
  class ResponseHeadersTest < Minitest::Test
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
      assert_equal '200', event.rate_limit_requests
      assert_equal '150000', event.rate_limit_tokens
      assert_equal '199', event.rate_limit_remaining_requests
      assert_equal '149990', event.rate_limit_remaining_tokens
      assert_equal '7m12s', event.rate_limit_reset_requests
      assert_equal '4ms', event.rate_limit_reset_tokens
    end
  end
end
