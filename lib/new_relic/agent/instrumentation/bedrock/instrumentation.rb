# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Bedrock
    def invoke_model_with_new_relic(params, options)
      # add instrumentation content here
      puts '&' * 100
      puts 'invoke_model_with_new_relic'
      @nr_events = []
      # metrics still

      segment = NewRelic::Agent::Tracer.start_segment(name: 'bedrock')
      response = NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
    ensure
      segment&.finish
      create_llm_events(segment, params, options, response)
      # binding.irb
    end

    ##################################################################

    def create_chat_events(shared, summary, messages, segment)
      summary_event = create_chat_completion_summary_event(shared, summary, segment)
      messages.each_with_index do |message, index|
        create_chat_completion_message_event(index, summary_event.id, shared, message)
      end
    end

    def create_chat_completion_summary_event(shared, attributes, segment)
      summary_event = NewRelic::Agent::Llm::ChatCompletionSummary.new(shared)
      @nr_events << summary_event
      summary_event.id = NewRelic::Agent::GuidGenerator.generate_guid
      # summary_event.api_key_last_four_digits = config&.credentials&.access_key_id[-4..-1] # todo maybe dont do this
      summary_event.request_max_tokens = attributes[:request_max_tokens]
      summary_event.response_number_of_messages = attributes[:response_number_of_messages]
      summary_event.request_model = shared[:response_model]
      summary_event.response_usage_total_tokens = attributes[:response_usage_total_tokens]
      summary_event.response_usage_prompt_tokens = attributes[:response_usage_prompt_tokens]
      summary_event.response_usage_completion_tokens = attributes[:response_usage_completion_tokens]
      summary_event.response_choices_finish_reason = attributes[:response_choices_finish_reason]
      summary_event.request_temperature = attributes[:request_temperature]
      summary_event.duration = segment&.duration
      summary_event.error = true if segment&.noticed_error

      summary_event.record

      summary_event
    end

    def create_chat_completion_message_event(index, completion_id, shared, attributes)
      message_event = NewRelic::Agent::Llm::ChatCompletionMessage.new(shared)
      @nr_events << message_event
      message_event.id = "#{shared[:request_id]}-#{index}"
      message_event.completion_id = completion_id
      message_event.sequence = index
      message_event.content = attributes[:content]
      message_event.role = attributes[:role]
      message_event.is_response = attributes[:is_response] if attributes[:is_response]

      message_event.record
    end

    ##################################################################

    def create_llm_events(segment, params, options, response)

      ###################

      body = JSON.parse(params[:body])
      response_body = JSON.parse(response.body.read)
      response.body.rewind # put the response back

      model = params[:model_id]


      puts model
      puts 'params: ' + params.to_s
      puts 'body: ' + body.to_s
      puts 'options:' + options.to_s
      puts 'response_body:' + response_body.to_s


      shared_attributes = create_shared_attributes(model)

      all_attributes = if model.start_with?('amazon.titan-text-')
        titan_attributes(body, response_body)
      elsif model.start_with?('anthropic.claude-')
        anthropic_attributes(body, response_body)
      elsif model.start_with?('cohere.command-')
        cohere_command_attributes(body, response_body)
      elsif model.start_with?('meta.llama2-')
        # llama2_attributes(params, options, result)
      elsif model.start_with?('ai21.j2-')
        # jurassic_attributes(params, options, result)
      # elsif model.start_with?('amazon.titan-embed-') 
      #   titan_embed_attributes(params, options, result)
      # elsif model.start_with?('cohere.embed-')
      #   cohere_embed_attributes(params, options, result)
      else
        # log something idk
        nil
      end

      create_chat_events(shared_attributes, *all_attributes, segment)

    rescue => e
      # log something
      puts 'oop'
      puts e
      puts e.backtrace
    end

    def create_shared_attributes(model)
      shared_attributes = {}

      shared_attributes[:request_id] = NewRelic::Agent::Tracer.current_transaction&.aws_request_id # todo better
      shared_attributes[:response_model] = model
      shared_attributes[:vendor] = 'bedrock'

      conversation_id = NewRelic::Agent::Tracer.current_transaction&.attributes&.custom_attributes&.[]('llm.conversation_id')
      shared_attributes[:conversation_id] = conversation_id if conversation_id

      shared_attributes
    end

    ##################################################################
    # Model attributes
    ##################################################################
    def titan_attributes(body, response_body)
      summary_attributes = {}

      summary_attributes[:request_max_tokens] = body['textGenerationConfig']['maxTokenCount']
      summary_attributes[:response_number_of_messages] = 1 + response_body['results'].length
      summary_attributes[:request_temperature] = body['textGenerationConfig']['temperature']
      summary_attributes[:response_usage_prompt_tokens] = response_body['inputTextTokenCount']
      # do we add all tokens from responses together?
      summary_attributes[:response_usage_total_tokens] = response_body['inputTextTokenCount'] + response_body['results'][0]['tokenCount']
      summary_attributes[:response_usage_completion_tokens] = response_body['results'][0]['tokenCount']
      summary_attributes[:response_choices_finish_reason] = response_body['results'][0]['completionReason']
      
      messages_attributes = []

      messages_attributes << {
        content: body['inputText'],
        role: 'user',
      }

      response_body['results'].each do |result|
        messages_attributes << {
          content: result['outputText'],
          role: 'assistant',
          is_response: true
        }
      end

      [summary_attributes, messages_attributes]
    end

    def anthropic_attributes(body, response_body)
      summary_attributes = {}

      summary_attributes[:request_max_tokens] = body['max_tokens_to_sample']
      summary_attributes[:response_number_of_messages] = 0
      summary_attributes[:request_temperature] = body['temperature']
      summary_attributes[:response_usage_prompt_tokens] = 0 # todo need from headers
      summary_attributes[:response_usage_completion_tokens] = 0 # todo  need from headers
      summary_attributes[:response_usage_total_tokens] =  summary_attributes[:response_usage_prompt_tokens] + summary_attributes[:response_usage_completion_tokens]
      summary_attributes[:response_choices_finish_reason] = response_body['stop_reason']
      
      messages_attributes = []

      messages_attributes << {
        content: body['prompt'],
        role: 'user',
      }

      messages_attributes << {
        content: result['completion'],
        role: 'assistant',
        is_response: true
      }


      [summary_attributes, messages_attributes]
    end

    def cohere_command_attributes(body, response_body)
      summary_attributes = {}

      # binding.irb
      summary_attributes[:request_max_tokens] = body['max_tokens']
      summary_attributes[:response_number_of_messages] = 0
      summary_attributes[:request_temperature] = body['temperature']
      summary_attributes[:response_usage_prompt_tokens] = 0 # todo need from headers
      summary_attributes[:response_usage_completion_tokens] = 0 # todo  need from headers
      summary_attributes[:response_usage_total_tokens] =  summary_attributes[:response_usage_prompt_tokens] + summary_attributes[:response_usage_completion_tokens]
      summary_attributes[:response_choices_finish_reason] = response_body['generations'][0]['finish_reason']
      
      messages_attributes = []


      response_body['generations'][0]['id'] # todo do we need this? response id? different from the one in the response header

      messages_attributes << {
        content: body['prompt'],
        role: 'user',
      }

      response_body['results'].each do |result|
        messages_attributes << {
          content: result['outputText'],
          role: 'assistant',
          is_response: true
        }
      end

      [summary_attributes, messages_attributes]
    end

    def llama2_attributes(body, response_body)
    end

    def jurassic_attributes(body, response_body)
    end

    # Embedding:
    # (only when model is amazon.titan-embed or cohere.embed)
    # input api_key_last_four_digits request_model
    # response_organization response_usage_total_tokens
    # response_usage_prompt_tokens duration error
    def titan_embed_attributes(body, response_body)
    end

    def cohere_embed_attributes(body, response_body)
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