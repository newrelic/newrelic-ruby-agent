# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Llm
      module ResponseHeaders
        ATTRIBUTES = %i[llm_version rate_limit_requests rate_limit_tokens
          rate_limit_remaining_requests rate_limit_remaining_tokens
          rate_limit_reset_requests rate_limit_reset_tokens]

        OPENAI_VERSION = 'openai-version'
        X_RATELIMIT_LIMIT_REQUESTS = 'x-ratelimit-limit-requests'
        X_RATELIMIT_LIMIT_TOKENS = 'x-ratelimit-limit-tokens'
        X_RATELIMIT_REMAINING_REQUESTS = 'x-ratelimit-remaining-requests'
        X_RATELIMIT_REMAINING_TOKENS = 'x-ratelimit-remaining-tokens'
        X_RATELIMIT_RESET_REQUESTS = 'x-ratelimit-reset-requests'
        X_RATELIMIT_RESET_TOKENS = 'x-ratelimit-reset-tokens'

        attr_accessor(*ATTRIBUTES)

        # Headers is a hash of Net::HTTP response headers
        def populate_openai_response_headers(headers)
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
