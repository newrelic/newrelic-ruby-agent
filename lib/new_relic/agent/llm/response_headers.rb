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

        attr_accessor(*ATTRIBUTES)

        # Headers is a hash of Net::HTTP response headers
        def populate_openai_response_headers(headers)
          self.llm_version = headers['openai-version']&.first
          self.rate_limit_requests = headers['x-ratelimit-limit-requests']&.first
          self.rate_limit_tokens = headers['x-ratelimit-limit-tokens']&.first
          self.rate_limit_remaining_requests = headers['x-ratelimit-remaining-requests']&.first
          self.rate_limit_remaining_tokens = headers['x-ratelimit-remaining-tokens']&.first
          self.rate_limit_reset_requests = headers['x-ratelimit-reset-requests']&.first
          self.rate_limit_reset_tokens = headers['x-ratelimit-reset-tokens']&.first
        end
      end
    end
  end
end
