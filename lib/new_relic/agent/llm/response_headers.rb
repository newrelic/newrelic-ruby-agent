# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Llm
      module ResponseHeaders
        ATTRIBUTES = %i[response_organization llm_version ratelimit_limit_requests
          ratelimit_limit_tokens ratelimit_remaining_requests
          ratelimit_remaining_tokens ratelimit_reset_requests
          ratelimit_reset_tokens ratelimit_limit_tokens_usage_based
          ratelimit_reset_tokens_usage_based
          ratelimit_remaining_tokens_usage_based]

        ATTRIBUTE_NAME_EXCEPTIONS = {
          response_organization: 'response.organization',
          llm_version: 'response.headers.llm_version',
          ratelimit_limit_requests: 'response.headers.ratelimitLimitRequests',
          ratelimit_limit_tokens: 'response.headers.ratelimitLimitTokens',
          ratelimit_remaining_requests: 'response.headers.ratelimitRemainingRequests',
          ratelimit_remaining_tokens: 'response.headers.ratelimitRemainingTokens',
          ratelimit_reset_requests: 'response.headers.ratelimitResetRequests',
          ratelimit_reset_tokens: 'response.headers.ratelimitResetTokens',
          ratelimit_limit_tokens_usage_based: 'response.headers.ratelimitLimitTokensUsageBased',
          ratelimit_reset_tokens_usage_based: 'response.headers.ratelimitResetTokensUsageBased',
          ratelimit_remaining_tokens_usage_based: 'response.headers.ratelimitRemainingTokensUsageBased'
        }

        OPENAI_ORGANIZATION = 'openai-organization'
        OPENAI_VERSION = 'openai-version'
        X_RATELIMIT_LIMIT_REQUESTS = 'x-ratelimit-limit-requests'
        X_RATELIMIT_LIMIT_TOKENS = 'x-ratelimit-limit-tokens'
        X_RATELIMIT_REMAINING_REQUESTS = 'x-ratelimit-remaining-requests'
        X_RATELIMIT_REMAINING_TOKENS = 'x-ratelimit-remaining-tokens'
        X_RATELIMIT_RESET_REQUESTS = 'x-ratelimit-reset-requests'
        X_RATELIMIT_RESET_TOKENS = 'x-ratelimit-reset-tokens'
        X_RATELIMIT_LIMIT_TOKENS_USAGE_BASED = 'x-ratelimit-limit-tokens-usage-based'
        X_RATELIMIT_RESET_TOKENS_USAGE_BASED = 'x-ratelimit-reset-tokens-usage-based'
        X_RATELIMIT_REMAINING_TOKENS_USAGE_BASED = 'x-ratelimit-remaining-tokens-usage-based'
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
          self.ratelimit_limit_requests = headers[X_RATELIMIT_LIMIT_REQUESTS]&.first&.to_i
          self.ratelimit_limit_tokens = headers[X_RATELIMIT_LIMIT_TOKENS]&.first&.to_i
          remaining_headers(headers)
          reset_headers(headers)
          tokens_usage_based_headers(headers)
        end

        private

        def remaining_headers(headers)
          self.ratelimit_remaining_requests = headers[X_RATELIMIT_REMAINING_REQUESTS]&.first&.to_i
          self.ratelimit_remaining_tokens = headers[X_RATELIMIT_REMAINING_TOKENS]&.first&.to_i
        end

        def reset_headers(headers)
          self.ratelimit_reset_requests = headers[X_RATELIMIT_RESET_REQUESTS]&.first
          self.ratelimit_reset_tokens = headers[X_RATELIMIT_RESET_TOKENS]&.first
        end

        def tokens_usage_based_headers(headers)
          self.ratelimit_limit_tokens_usage_based = headers[X_RATELIMIT_LIMIT_TOKENS_USAGE_BASED]&.first&.to_i
          self.ratelimit_reset_tokens_usage_based = headers[X_RATELIMIT_RESET_TOKENS_USAGE_BASED]&.first
          self.ratelimit_remaining_tokens_usage_based = headers[X_RATELIMIT_REMAINING_TOKENS_USAGE_BASED]&.first&.to_i
        end
      end
    end
  end
end
