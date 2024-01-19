# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'llm_event/chat_completion'

module NewRelic
  module Agent
    class LlmEvent

      # response_model looks like repsonse.model
      attr_accessor :id, :app_name, :request_id, :span_id, :transaction_id, :trace_id, :response_model, :vendor
      INGEST_SOURCE = 'Ruby'

      def initialize(id:, app_name:, request_id:, span_id:, transaction_id:, trace_id:, response_model:, vendor:, **args)
        @id = id
        @app_name = app_name
        @request_id = request_id
        @span_id = span_id
        @transaction_id = transaction_id
        @trace_id = trace_id
        @response_model = response_model
        @vendor = vendor
      end

      # Method for subclasses to override
      def record; end
    end
  end
end