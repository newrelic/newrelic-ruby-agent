# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module OpenAI
    VENDOR = 'OpenAI' # or SUPPORTBILITY_NAME? or both?
    EMBEDDINGS_PATH = '/embeddings'
    CHAT_COMPLETIONS_PATH = '/chat/completions'

    # This method is defined in the OpenAI::HTTP module that is included
    # only in the OpenAI::Client class
    def json_post_with_new_relic(path:, parameters:)
      NewRelic::Agent.record_instrumentation_invocation(VENDOR) # idk if this is quite the right spot, since it'll catch situations where the gem is invoked, but our instrumented methods aren't called?

      if path == EMBEDDINGS_PATH
        embeddings_instrumentation(parameters, headers)
        binding.irb

        segment = NewRelic::Agent::Tracer.start_segment(name: 'Llm/embedding/OpenAI/create')
        NewRelic::Agent.record_metric('Ruby/ML/OpenAI/6.3.1', 0.0)
        event = create_embedding_event(parameters)

        # segment.chat_completion_summary = event
        # create_chat_completion_messages(parameters)
        begin
          response = NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
          add_response_params(parameters, response, event)
          # binding.irb
          # event.whatever_attr_name = response[:find_me]
          # add attributes from the response body
          # create_chat_completion_messages(response) ??
          # set error:true if an error was raised
        ensure
          segment&.finish
          event&.error = true if segment&.instance_variable_get(:@notice_error) # need to test throwing an error
          event&.duration = segment&.duration
          event&.record # always record the event
        end
      ##################
      elsif path == CHAT_COMPLETIONS_PATH
        # binding.irb
        # chat_completions_instrumentation(parameters, headers)
        segment = NewRelic::Agent::Tracer.start_segment(name: 'Llm/completion/OpenAI/create')
        NewRelic::Agent.record_metric('Ruby/ML/OpenAI/6.3.1', 0.0)
        event = create_chat_completion_summary(parameters)
        segment.chat_completion_summary = event
        create_chat_completion_messages(parameters)
        begin
          response = NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
          add_response_params(parameters, response, event)
          # binding.irb
          # event.whatever_attr_name = response[:find_me]
          # add attributes from the response body
          # create_chat_completion_messages(response) ??
          # set error:true if an error was raised
        ensure
          segment&.finish
          event&.error = true if segment&.instance_variable_get(:@notice_error) # need to test throwing an error
          event&.duration = segment&.duration
          event&.record # always record the event
        end
      else
        # does this case work? request to non-endpoint?
        yield
      end
    end

    private

    def embeddings_instrumentation(parameters, request_headers)
      # TBD
      # yield
    end

    def create_chat_completion_summary(parameters)
      event = NewRelic::Agent::Llm::ChatCompletionSummary.new(
        vendor: VENDOR,
        id: NewRelic::Agent::GuidGenerator.generate_guid, # this can probably be moved to a shared module for embeddings/chat completions
        conversation_id: 'CHECK TO SEE IF TRANSACTION CUSTOM ATTRIBUTES HAS ME',
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

    def create_embedding_event
      # id	| NewRelic::Agent::GuidGenerator.generate_guid
      # request_id |response.headers.x-request-id
      # span_id	| NewRelic::Agent::Tracer.current_span_id
      # transaction_id | NewRelic::Agent::Tracer.current_transaction.guid
      # trace_id	| NewRelic::Agent::Tracer.current_trace_id
      # metadata | assigned	assigned via new set_llm_metadata API, access TBD
      # input	| request.params.input 
      # api_key_last_four_digits |	"within Http#json_post, call headers[:Authorization] | Prefix with sk-, take last 4 of key"
      # request.model |	parameters[:model]
      # response.model| response["model"]
      # response.usage.total_tokens	| response["usage"]["total_tokens"]
      # response.usage.prompt_tokens |	response["usage"]["prompt_tokens"]
      # vendor| static value openAI
      # ingest_source	| static value Ruby
      # response.headers.llmVersion	| set from response.headers.openai-version
      # response.headers.ratelimitLimitRequests	| set from response.headers.x-ratelimit-limit-requests
      # response.headers.ratelimitLimitTokens	| set from response.headers.x-ratelimit-limit-tokens
      # response.headers.ratelimitResetTokens	| set from response.headers.x-ratelimit-reset-tokens
      # response.headers.ratelimitResetRequests	| set from response.headers.x-ratelimit-reset-requests
      # response.headers.ratelimitRemainingTokens	| set from response.headers.x-ratelimit-remaining-tokens
      # response.headers.ratelimitRemainingRequests	| set from response.headers.x-ratelimit-remaining-requests
      # duration	| NewRelic::Agent::Tracer.current_segment.duration
      # error	| Boolean set to True if an error occurred during call 
    end

    def add_response_params(parameters, response, event)
      event.response_number_of_messages = parameters[:messages].size + response['choices'].size # is .size or .length more performant?
      event.response_model = response['model']
      event.response_usage_total_tokens = response['usage']['total_tokens']
      event.response_usage_prompt_tokens = response['usage']['prompt_tokens']
      event.response_usage_completion_tokens = response['usage']['completion_tokens']
      event.response_choices_finish_reason = response['choices'][0]['finish_reason']
    end


    # def chat_completions_instrumentation(parameters, request_headers)
    #   # TBD
    #   segment = NewRelic::Agent::Tracer.start_segment(name: 'Llm/completion/OpenAI/create')
    #   begin
    #     NewRelic::Agent::Tracer.capture_segment_error(segment) { super }
    #   ensure
    #     segment&.finish
    #   end
    # end
    def parse_api_key # probs define somewhere in Llm namespace?
      'sk-' + headers['Authorization'][-4..-1]
    end

    def create_chat_completion_messages(parameters) # can this be used for the request messages and the repsonse messages?
      parameters[:messages].each_with_index do |message, i|
        NewRelic::Agent::Llm::ChatCompletionMessage.new(
          id: 'response["id"] + index of parameters["message"] or response["choices"][0]["index"]',
          role: message[:role],
          content: message[:content],
          sequence: i,
          completion_id: 'special helper to get id of summary object'
        )
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
  end
end
