# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'llm_event/chat_completion'
require_relative 'llm_event/chat_completion/message'
require_relative 'llm_event/chat_completion/summary'
require_relative 'llm_event/embedding'
require_relative 'llm_event/feedback'
require_relative 'llm_event/response_headers'

module NewRelic
  module Agent
    class LlmEvent
      # response_model looks like repsonse.model
      INGEST_SOURCE = 'Ruby'

      def initialize(id: nil, request_id: nil, span_id: nil, transaction_id: nil, trace_id: nil, response_model: nil, vendor: nil, **args)
        @id = id
        @request_id = request_id
        @span_id = span_id
        @transaction_id = transaction_id
        @trace_id = trace_id
        @response_model = response_model
        @vendor = vendor
      end

      # TODO: make sure attribute keys match the spec, or are okay to be snake_case
      def llm_event_attributes
        {id: @id, request_id: @request_id, span_id: @span_id, transaction_id: @transaction_id,
         trace_id: @trace_id, response_model: @response_model, vendor: @vendor}
      end

      # Method for subclasses to override
      def record
      end
    end
  end
end
