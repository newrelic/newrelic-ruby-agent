# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module OpenAI
    VENDOR = 'openAI'
    EMBEDDINGS_PATH = '/embeddings'
    CHAT_COMPLETIONS_PATH = '/chat/completions'
    SEGMENT_NAME_FORMAT = 'Llm/%s/OpenAI/create' # TODO: Does the segment name need to end with the name of the method called by the customer?

    def json_post_with_new_relic(path:, parameters:)
      return yield unless path == EMBEDDINGS_PATH || path == CHAT_COMPLETIONS_PATH # do we need return?

      NewRelic::Agent.record_instrumentation_invocation(VENDOR)
      NewRelic::Agent::Llm::LlmEvent.set_llm_agent_attribute_on_transaction

      if path == EMBEDDINGS_PATH
        embeddings_instrumentation(parameters) { yield }
      elsif path == CHAT_COMPLETIONS_PATH
        chat_completions_instrumentation(parameters) { yield }
      end
    end

    private

    def embeddings_instrumentation(parameters)
      segment = NewRelic::Agent::Tracer.start_segment(name: SEGMENT_NAME_FORMAT % 'embedding')
      record_openai_metric
      event = create_embeddings_event(parameters)
      segment.embedding = event
      begin
        response = NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }

        response
      ensure
        add_embeddings_response_params(response, event) if response
        segment&.finish
        event&.error = true if segment_noticed_error?(segment)
        event&.duration = segment&.duration
        event&.record
      end
    end

    def chat_completions_instrumentation(parameters)
      segment = NewRelic::Agent::Tracer.start_segment(name: SEGMENT_NAME_FORMAT % 'completion')
      record_openai_metric
      event = create_chat_completion_summary(parameters)
      segment.chat_completion_summary = event
      messages = create_chat_completion_messages(parameters, event.id)

      begin
        # binding.irb
        response = NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
        # binding.irb
        add_response_params(parameters, response, event) if response
        messages = update_chat_completion_messages(messages, response, event) if response

        response
      ensure
        segment&.finish
        event&.error = true if segment_noticed_error?(segment)
        event&.duration = segment&.duration
        event&.record
        messages&.each { |m| m.record }
      end
    end

    def create_chat_completion_summary(parameters)
      NewRelic::Agent::Llm::ChatCompletionSummary.new(
        # metadata => TBD, create API
        vendor: VENDOR,
        conversation_id: conversation_id,
        api_key_last_four_digits: parse_api_key,
        request_max_tokens: parameters[:max_tokens] || parameters['max_tokens'],
        request_model: parameters[:model] || parameters['model'],
        temperature: parameters[:temperature] || parameters['temperature']
      )
    end

    def create_embeddings_event(parameters)
      NewRelic::Agent::Llm::Embedding.new(
        # metadata => TBD, create API
        vendor: VENDOR,
        input: parameters[:input] || parameters['input'],
        api_key_last_four_digits: parse_api_key,
        request_model: parameters[:model] || parameters['model']
      )
    end

    def add_response_params(parameters, response, event)
      event.response_number_of_messages = (parameters[:messages] || parameters['messages']).size + response['choices'].size
      event.response_model = response['model']
      event.response_usage_total_tokens = response['usage']['total_tokens']
      event.response_usage_prompt_tokens = response['usage']['prompt_tokens']
      event.response_usage_completion_tokens = response['usage']['completion_tokens']
      event.response_choices_finish_reason = response['choices'][0]['finish_reason']
    end

    def add_embeddings_response_params(response, event)
      event.response_model = response['model']
      event.response_usage_total_tokens = response['usage']['total_tokens']
      event.response_usage_prompt_tokens = response['usage']['prompt_tokens']
    end

    def parse_api_key
      'sk-' + headers['Authorization'][-4..-1]
    end

    # The customer must call add_custom_attributes with llm.conversation_id
    # before the transaction starts. Otherwise, the conversation_id will be nil
    def conversation_id
      return @nr_conversation_id if @nr_conversation_id

      @nr_conversation_id ||= NewRelic::Agent::Tracer.current_transaction.attributes.custom_attributes[NewRelic::Agent::Llm::LlmEvent::CUSTOM_ATTRIBUTE_CONVERSATION_ID]
    end

    def create_chat_completion_messages(parameters, summary_id)
      (parameters[:messages] || parameters['messages']).map.with_index do |message, i|
        NewRelic::Agent::Llm::ChatCompletionMessage.new(
          content: message[:content] || message['content'],
          role: message[:role] || message['role'],
          sequence: i,
          completion_id: summary_id,
          vendor: VENDOR,
          is_response: false
        )
      end
    end

    def create_chat_completion_response_messages(response, sequence_origin, summary_id)
      response['choices'].map.with_index(sequence_origin) do |choice, i|
        NewRelic::Agent::Llm::ChatCompletionMessage.new(
          content: choice['message']['content'],
          role: choice['message']['role'],
          sequence: i,
          completion_id: summary_id,
          vendor: VENDOR,
          is_response: true
        )
      end
    end

    def update_chat_completion_messages(messages, response, summary)
      messages += create_chat_completion_response_messages(response, messages.size, summary.id)
      response_id = response['id'] || NewRelic::Agent::GuidGenerator.generate_guid

      messages.each do |message|
        # metadata => TBD, create API
        message.id = "#{response_id}-#{message.sequence}"
        message.conversation_id = conversation_id
        message.request_id = summary.request_id
        message.response_model = response['model']
      end
    end

    # the preceding :: are necessary to access the OpenAI module defined in the gem rather than the current module
    # TODO: discover whether this metric name should be prepended with 'Supportability'
    def record_openai_metric
      NewRelic::Agent.record_metric("Ruby/ML/OpenAI/#{::OpenAI::VERSION}", 0.0)
    end

    def segment_noticed_error?(segment)
      segment&.instance_variable_get(:@noticed_error)
    end
  end
end
