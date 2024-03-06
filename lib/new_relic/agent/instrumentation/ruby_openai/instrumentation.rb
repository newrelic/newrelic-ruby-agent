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
        # TODO: Remove !response.include?('error') when we drop support for versions below 4.0.0
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
        # TODO: Remove !response.include?('error') when we drop support for versions below 4.0.0
        if response && !response.include?('error')
          add_chat_completion_response_params(parameters, response, event)
          messages = update_chat_completion_messages(messages, response, event, parameters)
        end

        response
      ensure
        finish(segment, event)
        messages&.each { |m| m.record }
      end
    end

    def create_chat_completion_summary(parameters)
      NewRelic::Agent::Llm::ChatCompletionSummary.new(
        vendor: VENDOR,
        request_max_tokens: parameters[:max_tokens] || parameters['max_tokens'],
        request_model: parameters[:model] || parameters['model'],
        temperature: parameters[:temperature] || parameters['temperature'],
        metadata: llm_custom_attributes
      )
    end

    def create_embeddings_event(parameters)
      NewRelic::Agent::Llm::Embedding.new(
        vendor: VENDOR,
        input: parameters[:input] || parameters['input'],
        request_model: parameters[:model] || parameters['model'],
        metadata: llm_custom_attributes
      )
    end

    def add_chat_completion_response_params(parameters, response, event)
      event.response_number_of_messages = (parameters[:messages] || parameters['messages']).size + response['choices'].size
      # The response hash always returns keys as strings, so we don't need to run an || check here
      event.response_model = response['model']
      event.response_choices_finish_reason = response['choices'][0]['finish_reason']
    end

    def add_embeddings_response_params(response, event)
      event.response_model = response['model']
      event.token_count = response.dig('usage', 'prompt_tokens') || NewRelic::Agent.llm_token_count_callback&.call({model: event.request_model, content: event.input})
    end

    def create_chat_completion_messages(parameters, summary_id)
      (parameters[:messages] || parameters['messages']).map.with_index do |message, index|
        NewRelic::Agent::Llm::ChatCompletionMessage.new(
          content: message[:content] || message['content'],
          role: message[:role] || message['role'],
          sequence: index,
          completion_id: summary_id,
          vendor: VENDOR
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

    def update_chat_completion_messages(messages, response, summary, parameters)
      messages += create_chat_completion_response_messages(response, messages.size, summary.id)
      response_id = response['id'] || NewRelic::Agent::GuidGenerator.generate_guid

      messages.each do |message|
        message.id = "#{response_id}-#{message.sequence}"
        message.request_id = summary.request_id
        message.response_model = response['model']
        message.metadata = llm_custom_attributes
        message.token_count = calculate_message_token_count(message, response, parameters)
      end
    end

    def calculate_message_token_count(message, response, parameters)
      # message is response
      # more than one message in response
      # use the callback
      # one message in response
      # use the usage object
      # message is request
      # more than one message in request
      # use the callback
      # one message in request
      # use the usage object

      request_message_length = (parameters['messages'] || parameters[:messages]).length

      response_message_length = response['choices'].length

      return NewRelic::Agent.llm_token_count_callback&.call({model: response['model'], content: message.content}) unless message.is_response && (request_message_length > 1)

      token_count = if message.is_response
        response.dig('usage', 'completion_tokens')
      else
        response.dig('usage', 'prompt_tokens')
      end

      return NewRelic::Agent.llm_token_count_callback&.call({model: response['model'], content: message.content}) if token_count.nil?

      token_count.to_i
    end

    def llm_custom_attributes
      attributes = NewRelic::Agent::Tracer.current_transaction&.attributes&.custom_attributes&.select { |k| k.to_s.match(/llm.*/) }

      attributes&.transform_keys! { |key| key[4..-1] }
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

    def llm_token_count_callback
      NewRelic::Agent.llm_token_count_callback
    end

    def build_llm_token_count_callback_hash(model, content)
      {model: model, content: content}
    end

    def finish(segment, event)
      segment&.finish

      return unless event

      if segment
        event.error = true if segment_noticed_error?(segment)
        event.duration = segment.duration
      end

      event.record
    end
  end
end
