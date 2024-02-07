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
      all_attributes = parse_attributes_by_model(params, options, response)
      create_all_events(all_attributes)
      response
    end

    ##################################################################
    
    def create_all_events(all_attributes)
      shared = all_attributes[0]
      summary = all_attributes[1]
      messages = all_attributes[2]

      summary_event = NewRelic::Agent::Llm::ChatCompletionSummary.new


      messages.each_with_index do |message, index|
        message_event = NewRelic::Agent::Llm::ChatCompletionMessage.new
        # message_event.content = message[:content]
        # message_event.role = message[:role]
        # message_event.sequence = index
        # message_event.completion_id = summary_event.id
        # message_event.is_response = message[:is_response] if message[:is_response]
        # message_event.save

      end

    end

    def parse_attributes_by_model(params, options, result)
      puts params[:model_id]
      puts 'params: ' + params.to_s
      puts 'options' + options.to_s
      puts 'result' + result.to_s

      ###################

      model = params[:model_id]
      if model.start_with?('amazon.titan-text-')
        titan_attributes(params, options, result)
      elsif model.start_with?('amazon.titan-embed-') # emdedding
        titan_embed_attributes(params, options, result)
      elsif model.start_with?('anthropic.claude-')
        anthropic_attributes(params, options, result)
      elsif model.start_with?('cohere.command-')
        cohere_command_attributes(params, options, result)
      elsif model.start_with?('cohere.embed-') # embedding
        cohere_embed_attributes(params, options, result)
      elsif model.start_with?('meta.llama2-')
        llama2_attributes(params, options, result)
      elsif model.start_with?('ai21.j2-')
        jurassic_attributes(params, options, result)
      else
        # log something idk
        nil
      end
    end

    # how node does id field
    # AWS Titan -         uuid + -[index of message]
    # Anthropic Claude -  uuid + -[index of message]
    # AI21 Labs -  response.id + -[index of message]
    # Cohere -     response.id + -[index of message]
    # Llama2 -            uuid + -[index of message]

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

    def titan_attributes(params, options, response)
      body = JSON.parse(params[:body])
      response_body = JSON.parse(response.body.read)
      response.body.rewind

      shared_attributes = {}
      # id
      # AWS Titan -         uuid + -[index of message]

      # LlmEvent attributes
      # cc_message.id             = cc_summary.id             = NewRelic::Agent::GuidGenerator.generate_guid # uuid -

      shared_attributes[:request_id] = 1
      shared_attributes[:response_model] = params[:model_id]
      shared_attributes[:vendor] = 'bedrock'
      shared_attributes[:ingest_source] = 'Ruby'

      # ChatCompletion attributes
      # Optional attribute that can be added to a transaction by a customer via add_custom_attribute API
      conversation_id = NewRelic::Agent::Tracer.current_transaction&.attributes&.custom_attributes&.[](NewRelic::Agent::Llm::LlmEvent::CUSTOM_ATTRIBUTE_CONVERSATION_ID)
      shared_attributes[:conversation_id] = conversation_id if conversation_id

      summary_attributes = {}

      summary_attributes[:api_key_last_four_digits] = 1 # 
      summary_attributes[:request_max_tokens] = body['maxTokenCount']
      summary_attributes[:response_number_of_messages] = 1 + response_body['results'].length
      summary_attributes[:request_model] = params[:model_id]
      summary_attributes[:response_organization] = 1 # headers
      summary_attributes[:response_usage_total_tokens] = response_body['inputTextTokenCount'] + response_body['results'][0]['tokenCount']
      summary_attributes[:response_usage_prompt_tokens] = response_body['inputTextTokenCount']
      # do we add all tokens from responses together?
      summary_attributes[:response_usage_completion_tokens] = response_body['results'][0]['tokenCount']
      summary_attributes[:response_choices_finish_reason] = response_body['results'][0]['completionReason']
      summary_attributes[:request_temperature] = body['temperature']
      summary_attributes[:duration] = 1
      # summary_attributes[:error] = true # only if an error happened

      # ChatCompletionMessage attributes

      messages_attributes = []

      # user input message
      messages_attributes << {
        content: body['inputText'],
        role: 'user',
        # sequence: 0
        # completion_id: 1, # id of summary
        # is_response: 1 # omitted if false
      }

      # new one for each result? but also like how do i get multiple results?
      response_body['results'].each_with_index do |result, index|
        messages_attributes << {
          content: result['outputText'],
          role: 'assistant',
          # sequence: index + 1,
          # completion_id: 1, # id of summary
          is_response: true

        }
      end

      [shared_attributes, summary_attributes, messages_attributes]
    end

    # Embedding:
    # (only when model is amazon.titan-embed or cohere.embed)
    # input api_key_last_four_digits request_model
    # response_organization response_usage_total_tokens
    # response_usage_prompt_tokens duration error
    def titan_embed_attributes(params, options, result)
    end

    def anthropic_attributes(params, options, result)
    end

    def cohere_command_attributes(params, options, result)
    end

    def cohere_embed_attributes(params, options, result)
    end

    def llama2_attributes(params, options, result)
    end

    def jurassic_attributes(params, options, result)
    end
  end


end
