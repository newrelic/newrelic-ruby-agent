# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class LlmEvent
      class ResponseHeaders < NewRelic::Agent::LlmEvent
        def initialize(llm_version: nil, rate_limit_requests: nil, rate_limit_tokens: nil,
          rate_limit_reset_requests: nil, rate_limit_reset_tokens: nil,
          rate_limit_remaining_requests: nil, rate_limit_remaining_tokens: nil)
          @llm_version = llm_version
          @rate_limit_requests = rate_limit_requests
          @rate_limit_tokens = rate_limit_tokens
          @rate_limit_reset_requests = rate_limit_reset_requests
          @rate_limit_reset_tokens = rate_limit_reset_tokens
          @rate_limit_remaining_requests = rate_limit_remaining_requests
          @rate_limit_remaining_tokens = rate_limit_remaining_tokens
        end

        # Headers is a hash of Net::HTTP response headers
        def populate_openai_response_headers(headers)
          @llm_version = headers['openai-version'][0]
          @rate_limit_requests = headers['x-ratelimit-limit-requests'][0]
          @rate_limit_tokens = headers['x-ratelimit-limit-tokens'][0]
          @rate_limit_reset_requests = headers['x-ratelimit-reset-requests'][0]
          @rate_limit_reset_tokens = headers['x-ratelimit-reset-tokens'][0]
          @rate_limit_remaining_requests = headers['x-ratelimit-remaining-requests'][0]
          @rate_limit_remaining_tokens = headers['x-ratelimit-remaining-tokens'][0]
        end

        # this reflects the string casing in the spec
        # we may or may not need to do it this way
        # if we need to do it like this, we should update the
        # attribute methods in the other classes
        def attributes
          {
            :'response.headers.llmVersion' => @llm_version,
            :'response.headers.rateLimitRequests' => @rate_limit_requests,
            :'response.headers.rateLimitTokens' => @rate_limit_tokens,
            :'response.headers.rateLimitResetRequests' => @rate_limit_reset_requests,
            :'response.headers.rateLimitResetTokens' => @rate_limit_reset_tokens,
            :'response.headers.rateLimitRemainingRequests' => @rate_limit_remaining_requests,
            :'response.headers.rateLimitRemainingTokens' => @rate_limit_remaining_tokens
          }
        end
      end
    end
  end
end
