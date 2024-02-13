# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module OpenAI
    VENDOR = 'openAI' # AIM expects this capitalization style for the UI
    INSTRUMENTATION_NAME = NewRelic::Agent.base_name(name)
    EMBEDDINGS_PATH = '/embeddings'
    CHAT_COMPLETIONS_PATH = '/chat/completions'
    EMBEDDINGS_SEGMENT_NAME = 'Llm/embedding/OpenAI/embeddings'
    CHAT_COMPLETIONS_SEGMENT_NAME = 'Llm/completion/OpenAI/chat'

    def json_post_with_new_relic(path:, parameters:)
      return yield unless path == EMBEDDINGS_PATH || path == CHAT_COMPLETIONS_PATH

      NewRelic::Agent.record_instrumentation_invocation(INSTRUMENTATION_NAME)
      NewRelic::Agent::Llm::LlmEvent.set_llm_agent_attribute_on_transaction

      if path == EMBEDDINGS_PATH
        embeddings_instrumentation(parameters) { yield }
      elsif path == CHAT_COMPLETIONS_PATH
        chat_completions_instrumentation(parameters) { yield }
      end
    end

    private

    def embeddings_instrumentation(parameters)
      segment = NewRelic::Agent::Tracer.start_segment(name: EMBEDDINGS_SEGMENT_NAME)
      record_openai_metric
      event = create_embeddings_event(parameters)
      segment.llm_event = event
      begin
        response = NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
        # TODO: Remove !response.include?('error) when we drop support for versions below 4.0.0
        add_embeddings_response_params(response, event) if response && !response.include?('error')

        response
      ensure
        finish(segment, event)
      end
    end

    def chat_completions_instrumentation(parameters)
      segment = NewRelic::Agent::Tracer.start_segment(name: CHAT_COMPLETIONS_SEGMENT_NAME)
      record_openai_metric
      event = create_chat_completion_summary(parameters)
      segment.llm_event = event
      messages = create_chat_completion_messages(parameters, event.id)

      begin
        response = NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
        # TODO: Remove !response.include?('error) when we drop support for versions below 4.0.0
        if response && !response.include?('error')
          add_chat_completion_response_params(parameters, response, event)
          messages = update_chat_completion_messages(messages, response, event)
        end

        response
      ensure
        finish(segment, event)
        messages&.each { |m| m.record }
      end
    end

    def create_chat_completion_summary(parameters)
      NewRelic::Agent::Llm::ChatCompletionSummary.new(
        # TODO: POST-GA: Add metadata from add_custom_attributes if prefixed with 'llm.', except conversation_id
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
        # TODO: POST-GA: Add metadata from add_custom_attributes if prefixed with 'llm.', except conversation_id
        vendor: VENDOR,
        input: parameters[:input] || parameters['input'],
        api_key_last_four_digits: parse_api_key,
        request_model: parameters[:model] || parameters['model']
      )
    end

    def add_chat_completion_response_params(parameters, response, event)
      event.response_number_of_messages = (parameters[:messages] || parameters['messages']).size + response['choices'].size
      # The response hash always returns keys as strings, so we don't need to run an || check here
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
    # before the transaction starts. Otherwise, the conversation_id will be nil.
    def conversation_id
      return @nr_conversation_id if @nr_conversation_id

      @nr_conversation_id ||= NewRelic::Agent::Tracer.current_transaction.attributes.custom_attributes[NewRelic::Agent::Llm::LlmEvent::CUSTOM_ATTRIBUTE_CONVERSATION_ID]
    end

    def create_chat_completion_messages(parameters, summary_id)
      (parameters[:messages] || parameters['messages']).map.with_index do |message, index|
        NewRelic::Agent::Llm::ChatCompletionMessage.new(
          content: message[:content] || message['content'],
          role: message[:role] || message['role'],
          sequence: index,
          completion_id: summary_id,
          vendor: VENDOR,
          is_response: false
        )
      end
    end

    def create_chat_completion_response_messages(response, sequence_origin, summary_id)
      response['choices'].map.with_index(sequence_origin) do |choice, index|
        NewRelic::Agent::Llm::ChatCompletionMessage.new(
          content: choice['message']['content'],
          role: choice['message']['role'],
          sequence: index,
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
        # TODO: POST-GA: Add metadata from add_custom_attributes if prefixed with 'llm.', except conversation_id
        message.id = "#{response_id}-#{message.sequence}"
        message.conversation_id = conversation_id
        message.request_id = summary.request_id
        message.response_model = response['model']
      end
    end

    def record_openai_metric
      NewRelic::Agent.record_metric(nr_supportability_metric, 0.0)
    end

    def segment_noticed_error?(segment)
      segment&.instance_variable_get(:@noticed_error)
    end

    def nr_supportability_metric
      @nr_supportability_metric ||= "Supportability/Ruby/ML/OpenAI/#{::OpenAI::VERSION}"
    end

    def finish(segment, event)
      segment&.finish
      event&.error = true if segment_noticed_error?(segment)
      event&.duration = segment&.duration
      event&.record
    end
  end
end
