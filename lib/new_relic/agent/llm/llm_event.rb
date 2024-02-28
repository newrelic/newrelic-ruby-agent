# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Llm
      class LlmEvent
        # Every subclass must define its own ATTRIBUTES constant, an array of symbols representing
        # that class's unique attributes
        ATTRIBUTES = %i[id request_id span_id transaction_id trace_id
          response_model vendor ingest_source]
        # These attributes should not be passed as arguments to initialize and will be set by the agent
        AGENT_DEFINED_ATTRIBUTES = %i[span_id transaction_id trace_id ingest_source]
        # Some attributes have names that can't be written as symbols used for metaprogramming.
        # The ATTRIBUTE_NAME_EXCEPTIONS hash should use the symbolized version of the name as the key
        # and the string version expected by the UI as the value.
        ATTRIBUTE_NAME_EXCEPTIONS = {response_model: 'response.model'}
        INGEST_SOURCE = 'Ruby'
        LLM = :llm

        attr_accessor(*ATTRIBUTES)

        def self.set_llm_agent_attribute_on_transaction
          NewRelic::Agent::Transaction.add_agent_attribute(LLM, true, NewRelic::Agent::AttributeFilter::DST_TRANSACTION_EVENTS)
        end

        # This initialize method is used for all subclasses.
        # It leverages the subclass's `attributes` method to iterate through
        # all the attributes for that subclass.
        # It assigns instance variables for all arguments passed to the method.
        # It also assigns agent-defined attributes.
        def initialize(opts = {})
          (attributes - AGENT_DEFINED_ATTRIBUTES).each do |attr|
            instance_variable_set(:"@#{attr}", opts[attr]) if opts.key?(attr)
          end

          @id = id || NewRelic::Agent::GuidGenerator.generate_guid
          @span_id = NewRelic::Agent::Tracer.current_span_id
          @transaction_id = NewRelic::Agent::Tracer.current_transaction&.guid
          @trace_id = NewRelic::Agent::Tracer.current_trace_id
          @ingest_source = INGEST_SOURCE
        end

        # All subclasses use event_attributes to get a full hash of all
        # attributes and their values
        def event_attributes
          attributes.each_with_object({}) do |attr, hash|
            hash[replace_attr_with_string(attr)] = instance_variable_get(:"@#{attr}")
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

        # Some attribute names include periods, which aren't valid values for
        # Ruby method names. This method returns a Hash with the key as the
        # Ruby symbolized version of the attribute and the value as the
        # period-delimited string expected upstream.
        def attribute_name_exceptions
          ATTRIBUTE_NAME_EXCEPTIONS
        end

        def record
          NewRelic::Agent.record_custom_event(event_name, event_attributes)
        end

        private

        def replace_attr_with_string(attr)
          return attribute_name_exceptions[attr] if attribute_name_exceptions.key?(attr)

          attr
        end
      end
    end
  end
end
