# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Bedrock
    def invoke_model_with_new_relic(params, options)
      # add instrumentation content here
      puts '&' * 100
      puts 'invoke_model_with_new_relic'

      # make a span or smthng
      response = yield
      create_llm_events(params, options, response)
      response
    end

    ##################################################################

    def create_chat_events(shared, summary, messages)
      summary_event = create_chat_completion_summary_event(shared, summary)
      messages.each do |message|
        create_chat_completion_message_event(shared, summary_event.id, message)
      end
    end

    def create_chat_completion_summary_event(shared, attributes)
      summary_event = NewRelic::Agent::Llm::ChatCompletionSummary.new(shared)
      summary_event.id = NewRelic::Agent::GuidGenerator.generate_guid
      summary_event.api_key_last_four_digits = attributes[:api_key_last_four_digits]
      summary_event.request_max_tokens = attributes[:request_max_tokens]
      summary_event.response_number_of_messages = attributes[:response_number_of_messages]
      summary_event.request_model = attributes[:request_model]
      summary_event.response_organization = attributes[:response_organization]
      summary_event.response_usage_total_tokens = attributes[:response_usage_total_tokens]
      summary_event.response_usage_prompt_tokens = attributes[:response_usage_prompt_tokens]
      summary_event.response_usage_completion_tokens = attributes[:response_usage_completion_tokens]
      summary_event.response_choices_finish_reason = attributes[:response_choices_finish_reason]
      summary_event.request_temperature = attributes[:request_temperature]
      summary_event.duration = attributes[:duration]
      # summary_event.error = attributes[:error] if attributes[:error]
      # summary_event.record

      summary_event
    end

    def create_chat_completion_message_event(shared, completion_id, attributes)
      message_event = NewRelic::Agent::Llm::ChatCompletionMessage.new(shared)
      message_event.id = attributes[:id]
      message_event.request_id = attributes[:request_id]
      message_event.completion_id = completion_id
      message_event.sequence = attributes[:sequence]
      message_event.content = attributes[:content]
      message_event.role = attributes[:role]
      message_event.is_response = attributes[:is_response] if attributes[:is_response]
      # message_event.record
    end

    ##################################################################

    def create_llm_events(params, options, result)
      puts params[:model_id]
      puts 'params: ' + params.to_s
      puts 'options' + options.to_s
      puts 'result' + result.to_s

      ###################

      model = params[:model_id]
      all_attributes = if model.start_with?('amazon.titan-text-')
        titan_attributes(params, options, result)
      elsif model.start_with?('anthropic.claude-')
        anthropic_attributes(params, options, result)
      elsif model.start_with?('cohere.command-')
        cohere_command_attributes(params, options, result)
      elsif model.start_with?('meta.llama2-')
        llama2_attributes(params, options, result)
      elsif model.start_with?('ai21.j2-')
        jurassic_attributes(params, options, result)
      # elsif model.start_with?('amazon.titan-embed-') 
      #   titan_embed_attributes(params, options, result)
      # elsif model.start_with?('cohere.embed-')
      #   cohere_embed_attributes(params, options, result)
      else
        # log something idk
        nil
      end

      create_chat_events(*all_attributes)
    end

    ##################################################################
    def titan_attributes(params, options, response)
      body = JSON.parse(params[:body])
      response_body = JSON.parse(response.body.read)
      response.body.rewind

      shared_attributes = {}

      shared_attributes[:request_id] = 1 #idk
      shared_attributes[:response_model] = params[:model_id]
      shared_attributes[:vendor] = 'bedrock'

      conversation_id = NewRelic::Agent::Tracer.current_transaction&.attributes&.custom_attributes&.[](NewRelic::Agent::Llm::LlmEvent::CUSTOM_ATTRIBUTE_CONVERSATION_ID)
      shared_attributes[:conversation_id] = conversation_id if conversation_id

      summary_attributes = {}

      summary_attributes[:request_max_tokens] = body['maxTokenCount']
      summary_attributes[:response_number_of_messages] = 1 + response_body['results'].length
      summary_attributes[:request_model] = params[:model_id]
      summary_attributes[:response_usage_total_tokens] = response_body['inputTextTokenCount'] + response_body['results'][0]['tokenCount']
      summary_attributes[:response_usage_prompt_tokens] = response_body['inputTextTokenCount']
      # do we add all tokens from responses together?
      summary_attributes[:response_usage_completion_tokens] = response_body['results'][0]['tokenCount']
      summary_attributes[:response_choices_finish_reason] = response_body['results'][0]['completionReason']
      summary_attributes[:request_temperature] = body['temperature']
      
      #todo attrs
      summary_attributes[:api_key_last_four_digits] = 1 # 
      summary_attributes[:response_organization] = 1 # headers
      summary_attributes[:duration] = 1
      # summary_attributes[:error] = true # only if an error happened

      messages_attributes = []

      # pre_id = response_id if available
      pre_id = NewRelic::Agent::GuidGenerator.generate_guid

      # user input message
      messages_attributes << {
        content: body['inputText'],
        role: 'user',
        sequence: 0,
        id: "#{pre_id}-0"
      }

      # new one for each result? but also like how do i get multiple results?
      response_body['results'].each_with_index do |result, index|
        messages_attributes << {
          content: result['outputText'],
          role: 'assistant',
          sequence: index + 1,
          id: "#{pre_id}-#{index + 1}"
          is_response: true
        }
      end

      [shared_attributes, summary_attributes, messages_attributes]
    end

    def anthropic_attributes(params, options, result)
    end

    def cohere_command_attributes(params, options, result)
    end

    def llama2_attributes(params, options, result)
    end

    def jurassic_attributes(params, options, result)
    end

    # Embedding:
    # (only when model is amazon.titan-embed or cohere.embed)
    # input api_key_last_four_digits request_model
    # response_organization response_usage_total_tokens
    # response_usage_prompt_tokens duration error
    def titan_embed_attributes(params, options, result)
    end

    def cohere_embed_attributes(params, options, result)
    end
  end
end



    # LlmEvent:
    # id request_id span_id transaction_id trace_id response_model vendor ingest_source

    # ChatCompletion:
    # conversation_id (Optional attribute that can be added to a transaction by a customer via add_custom_attribute API)

    # ChatCompletionMessage:
    # content role sequence completion_id is_response

    # how node does content:
    # AWS Titan - params.inputText. On response map of response[n].outputText
    # Anthropic Claude - params.prompt. On response response.completion
    # AI21 Labs - params.prompt. On response map of response.completions[n].data.text
    # Cohere - params.prompt. On response map of response.generations[n].text
    # Llama2 - params.prompt . On response response.generation

    # ChatCompletionSummary:
    # api_key_last_four_digits request_max_tokens
    # response_number_of_messages request_model response_organization
    # response_usage_total_tokens response_usage_prompt_tokens
    # response_usage_completion_tokens response_choices_finish_reason
    # request_temperature duration error