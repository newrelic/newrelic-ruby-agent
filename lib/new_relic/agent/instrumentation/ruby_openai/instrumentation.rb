# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module OpenAI
    VENDOR = 'OpenAI' # or SUPPORTBILITY_NAME? or both?
    EMBEDDINGS_PATH = '/embeddings' # should everything below be called embeddings if we renamed to chat completions?
    CHAT_COMPLETIONS_PATH = '/chat/completions'

    # This method is defined in the OpenAI::HTTP module that is included
    # only in the OpenAI::Client class
    def json_post_with_new_relic(path:, parameters:)
      NewRelic::Agent.record_instrumentation_invocation(VENDOR) # idk if this is quite the right spot, since it'll catch situations where the gem is invoked, but our instrumented methods aren't called?

      if path == EMBEDDINGS_PATH
        embedding_instrumentation(parameters) { yield }
      elsif path == CHAT_COMPLETIONS_PATH
        chat_completions_instrumentation(parameters) { yield }
      else
        # does this case work? request to non-endpoint?
        yield
      end
    end

    private

    def embedding_instrumentation(parameters)
      segment = NewRelic::Agent::Tracer.start_segment(name: 'Llm/embedding/OpenAI/create')
      record_openai_metric
      event = create_embedding_event(parameters)
      segment.embedding = event
      begin
        response = NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
      ensure
        add_embedding_response_params(response, event) if response
        segment&.finish
        event&.error = true if segment_noticed_error? # need to test throwing an error
        event&.duration = segment&.duration
        event&.record # always record the event
        super # ?? that's what record_metrics, the last part of finishing the segment does
      end
    end

    def chat_completions_instrumentation(parameters)
      segment = NewRelic::Agent::Tracer.start_segment(name: 'Llm/completion/OpenAI/create')
      record_openai_metric
      event = create_chat_completion_summary(parameters)
      segment.chat_completion_summary = event
      summary_event_id = event.id
      messages = create_chat_completion_messages(parameters, summary_event_id)
      begin
        response = NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
        add_response_params(parameters, response, event) if response
        messages = update_chat_completion_messages(messages, response, summary_event_id) if response
      ensure
        segment&.finish
        event&.error = true if segment_noticed_error? # need to test throwing an error
        event&.duration = segment&.duration
        event&.record # always record the event
        messages&.each { |m| m&.record }
        super ## ?? that's what record_metrics, the last part of finishing the segment does
      end
    end

    def create_chat_completion_summary(parameters)
      event = NewRelic::Agent::Llm::ChatCompletionSummary.new(
        vendor: VENDOR,
        conversation_id: conversation_id,
        api_key_last_four_digits: parse_api_key,
        request_max_tokens: parameters[:max_tokens], # figure out how to access this in case it's a string
        request_model: parameters[:model],
        temperature: parameters[:temperature]
      )
      # request_id => net::http connection
      # span_id => assigned by llm_event
      # transation_id => assigned by llm_event
      # trace_id => assigned by llm_event
      # llm_metadata => assigned via API to be created
    end

    def create_embedding_event(parameters)
      event = NewRelic::Agent::Llm::Embedding.new(
        vendor: VENDOR,
        input: parameters[:input],
        api_key_last_four_digits: parse_api_key,
        request_model: parameters[:model]
      )
      # request_id | net::http connection
      # span_id	| assigned by llm_event
      # transaction_id | assigned by llm_event
      # trace_id	| assigned by llm_event
      # metadata | assigned via API to be created
    end

    def add_response_params(parameters, response, event)
      event.response_number_of_messages = parameters[:messages].size + response['choices'].size # is .size or .length more performant?
      event.response_model = response['model']
      # TODO: A usage object may not always be returned by the LLM.
      # In this case, the value of `response.usage.total_tokens` will need to be
      # calculated by adding together the input and output token counts. If
      # these values are unavailable, the value of this attribute should be null.
      event.response_usage_total_tokens = response['usage']['total_tokens']
      event.response_usage_prompt_tokens = response['usage']['prompt_tokens']
      event.response_usage_completion_tokens = response['usage']['completion_tokens']
      event.response_choices_finish_reason = response['choices'][0]['finish_reason']
    end

    def add_embedding_response_params(response, event)
      event.response_model = response['model']
      event.response_usage_total_tokens = response['usage']['total_tokens']
      event.response_usage_prompt_tokens = response['usage']['prompt_tokens']
    end

    def parse_api_key # probs define somewhere in Llm namespace?
      'sk-' + headers['Authorization'][-4..-1]
    end

    def conversation_id
      return @nr_conversation_id if @nr_conversation_id

      @nr_conversation_id ||= NewRelic::Agent::Tracer.current_transaction.attributes.custom_attributes['conversation_id']
    end
    # don't want diff conversation_id b/w summary and message

    def create_chat_completion_messages(parameters, summary_id) # can this be used for the request messages and the repsonse messages?, let's take off the key if not
      parameters[:messages].map.with_index do |message, i|
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

    def update_chat_completion_messages(messages, response, summary_id)
      messages += create_chat_completion_response_messages(response, messages.size, summary_id) # need to fix the sequence, possibly
      # now we have all the messages from the entire exchange
      response_id = response['id'] || NewRelic::Agent::GuidGenerator.generate_guid
      messages.each do |message|
        message.id = "#{response_id}-#{message.sequence}"
        message.conversation_id = conversation_id
        # message.request_id = # needs to be assigned from the net::http response, or passed from the summary object
        # metadata => TBD, create API
        message.response_model = response['model']
      end
    end

    # Name is defined in Ruby 3.0+
    # copied from rails code
    # Parameter keys might be symbols and might be strings
    # response body keys have always been strings
    def hash_with_indifferent_access_whatever
      if Symbol.method_defined?(:name)
        key.kind_of?(Symbol) ? key.name : key
      else
        key.kind_of?(Symbol) ? key.to_s : key
      end
    end

    # the preceding :: are necessary to access the OpenAI module defined in the gem rather than the current module
    def record_openai_metric
      NewRelic::Agent.record_metric("Ruby/ML/OpenAI/#{::OpenAI::VERSION}", 0.0)
    end

    def segment_noticed_error?
      segment&.instance_variable_get(:@notice_error)
    end
  end
end
