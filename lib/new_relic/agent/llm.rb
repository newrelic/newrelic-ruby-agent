# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'llm/llm_event'
require_relative 'llm/chat_completion_message'
require_relative 'llm/chat_completion_summary'
require_relative 'llm/embedding'
require_relative 'llm/response_headers'

module NewRelic
  module Agent
    class LLM
      INPUT = 'input'
      CONTENT = 'content'

      def self.instrumentation_enabled?
        NewRelic::Agent.config[:'ai_monitoring.enabled']
      end

      # LLM content-related attributes are exempt from the 4095 byte limit
      def self.exempt_event_attribute?(type, key)
        return false unless instrumentation_enabled?

        (type == NewRelic::Agent::Llm::Embedding::EVENT_NAME && key == INPUT) ||
          (type == NewRelic::Agent::Llm::ChatCompletionMessage::EVENT_NAME && key == CONTENT)
      end
    end
  end
end
