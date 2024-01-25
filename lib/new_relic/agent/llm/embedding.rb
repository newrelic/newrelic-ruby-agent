# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Llm
      class Embedding < LlmEvent
        include ResponseHeaders

        ATTRIBUTES = %i[api_key_last_four_digits input request_model
          response_organization response_usage_total_tokens
          response_usage_prompt_tokens duration error]
        EVENT_NAME = 'LlmEmbedding'

        attr_accessor(*ATTRIBUTES)

        def attributes
          LlmEvent::ATTRIBUTES + ResponseHeaders::ATTRIBUTES + ATTRIBUTES
        end

        def record
          NewRelic::Agent.record_custom_event(EVENT_NAME, event_attributes)
        end
      end
    end
  end
end
