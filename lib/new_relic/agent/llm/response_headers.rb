# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Llm
      module ResponseHeaders
        ATTRIBUTES = %i[response_organization llm_version rate_limit_requests
          rate_limit_tokens rate_limit_remaining_requests
          rate_limit_remaining_tokens rate_limit_reset_requests
          rate_limit_reset_tokens]
        ATTRIBUTE_NAME_EXCEPTIONS = {
          response_organization: 'response.organization',
          llm_version: 'response.headers.llm_version',
          rate_limit_requests: 'response.headers.ratelimitLimitRequests',
          rate_limit_tokens: 'response.headers.ratelimitLimitTokens',
          rate_limit_remaining_requests: 'response.headers.ratelimitRemainingRequests',
          rate_limit_remaining_tokens: 'response.headers.ratelimitRemainingTokens',
          rate_limit_reset_requests: 'response.headers.ratelimitResetRequests',
          rate_limit_reset_tokens: 'response.headers.ratelimitResetTokens'
        }

        OPENAI_ORGANIZATION = 'openai-organization'
        OPENAI_VERSION = 'openai-version'
        X_RATELIMIT_LIMIT_REQUESTS = 'x-ratelimit-limit-requests'
        X_RATELIMIT_LIMIT_TOKENS = 'x-ratelimit-limit-tokens'
        X_RATELIMIT_REMAINING_REQUESTS = 'x-ratelimit-remaining-requests'
        X_RATELIMIT_REMAINING_TOKENS = 'x-ratelimit-remaining-tokens'
        X_RATELIMIT_RESET_REQUESTS = 'x-ratelimit-reset-requests'
        X_RATELIMIT_RESET_TOKENS = 'x-ratelimit-reset-tokens'
        X_REQUEST_ID = 'x-request-id'

        attr_accessor(*ATTRIBUTES)

        # Headers is a hash of Net::HTTP response headers
        def populate_openai_response_headers(headers)
          # Embedding, ChatCompletionSummary, and ChatCompletionMessage all need
          # request_id, so it's defined in LlmEvent. ChatCompletionMessage
          # adds the attribute via ChatCompletionSummary.
          self.request_id = headers[X_REQUEST_ID]&.first
          self.response_organization = headers[OPENAI_ORGANIZATION]&.first
          self.llm_version = headers[OPENAI_VERSION]&.first
          self.rate_limit_requests = headers[X_RATELIMIT_LIMIT_REQUESTS]&.first
          self.rate_limit_tokens = headers[X_RATELIMIT_LIMIT_TOKENS]&.first
          self.rate_limit_remaining_requests = headers[X_RATELIMIT_REMAINING_REQUESTS]&.first
          self.rate_limit_remaining_tokens = headers[X_RATELIMIT_REMAINING_TOKENS]&.first
          self.rate_limit_reset_requests = headers[X_RATELIMIT_RESET_REQUESTS]&.first
          self.rate_limit_reset_tokens = headers[X_RATELIMIT_RESET_TOKENS]&.first
        end
      end
    end
  end
end
