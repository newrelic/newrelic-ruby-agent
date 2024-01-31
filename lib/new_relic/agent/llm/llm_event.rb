# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Llm
      class LlmEvent
        # Every subclass must define its own ATTRIBUTES constant, an array of symbols representing
        # that class's unique attributes
        ATTRIBUTES = %i[id request_id span_id transaction_id
          trace_id response_model vendor ingest_source]
        # These attributes should not be passed as arguments to initialize and will be set by the agent
        AGENT_DEFINED_ATTRIBUTES = %i[span_id transaction_id trace_id ingest_source]
        EXPORT_ATTRIBUTE_NAME = {
          response_number_of_messages: 'response.number_of_messages',
          request_model: 'request.model',
          response_model: 'response.model',
          response_usage_total_tokens: 'response.usage.total_tokens',
          response_usage_prompt_tokens: 'response.usage.prompt_tokens',
          response_usage_completion_tokens: 'response.usage.completion_tokens',
          response_choices_finish_reason: 'response.choices.finish_reason',
          llm_version: 'response.headers.llm_version',
          rate_limit_requests: 'response.headers.ratelimitLimitRequests',
          rate_limit_tokens: 'response.headers.ratelimitLimitTokens',
          rate_limit_reset_requests: 'response.headers.ratelimitResetRequests',
          rate_limit_reset_tokens: 'response.headers.ratelimitResetTokens',
          rate_limit_remaining_requests: 'response.headers.ratelimitRemainingRequests',
          rate_limit_remaining_tokens: 'response.headers.ratelimitRemainingRequests'
        }
        INGEST_SOURCE = 'Ruby'
        X_REQUEST_ID = 'x-request-id'

        attr_accessor(*ATTRIBUTES)

        # This initialize method is used for all subclasses.
        # It leverages the subclass's `attributes` method to iterate through
        # all the attributes for that subclass.
        # It assigns instance variables for all arguments passed to the method.
        # It also assigns agent-defined attributes.
        def initialize(opts = {})
          (attributes - AGENT_DEFINED_ATTRIBUTES).each do |attr|
            instance_variable_set(:"@#{attr}", opts[attr]) if opts.key?(attr)
          end

          @span_id = NewRelic::Agent::Tracer.current_span_id
          @transaction_id = NewRelic::Agent::Tracer.current_transaction&.guid
          @trace_id = NewRelic::Agent::Tracer.current_trace_id
          @ingest_source = INGEST_SOURCE
        end

        # All subclasses use event_attributes to get a full hash of all
        # attributes and their values
        def event_attributes
          attributes.each_with_object({}) do |attr, hash|
            hash[attr] = instance_variable_get(:"@#{attr}")
          end
        end

        # Subclasses define an attributes method to concatenate attributes
        # defined across their ancestors and other modules
        def attributes
          ATTRIBUTES
        end

        # Subclasses that record events will override this method
        def event_name
        end

        def record
          NewRelic::Agent.record_custom_event(event_name, event_attributes)
        end
      end
    end
  end
end
