# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Bedrock
    def invoke_model_with_new_relic(params, options)
      # add instrumentation content here
      puts "&" * 100
      puts "invoke_model_with_new_relic"

      response = yield
      parse_attributes_by_model(params, options, response)
      response
    end

    def parse_attributes_by_model(params, options, result)
      puts params[:model_id]
      puts "params: " + params.to_s
      puts "options" + options.to_s
      puts "result" + result.to_s
      @nr_attributes = {}
      ###################
      model = params[:model_id]
      if model.start_with?('amazon.titan-text-')
        titan_attributes(params, options, result)
      elsif model.start_with?('amazon.titan-embed-')# emdedding
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
        # unknown model
        'unknown model'
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


    def titan_attributes(params, options, result)

      cc_message = NewRelic::Agent::Llm::ChatCompletionMessage.new
      cc_summary = NewRelic::Agent::Llm::ChatCompletionSummary.new

      # id 
      # AWS Titan -         uuid + -[index of message] 

      # LlmEvent attributes
      cc_message.id             = cc_summary.id             = NewRelic::Agent::GuidGenerator.generate_guid # uuid - 
      cc_message.request_id     = cc_summary.request_id     = 1 # response headers prbly
      cc_message.response_model = cc_summary.response_model = params[:model_id]
      cc_message.vendor         = cc_summary.vendor         = 'bedrock'
      cc_message.ingest_source  = cc_summary.ingest_source  = 'Ruby'

      # ChatCompletion attributes
      # Optional attribute that can be added to a transaction by a customer via add_custom_attribute API
      # cc_message.conversation_id = cc_summary.conversation_id = 1

      # ChatCompletionMessage attributes
      body = JSON.parse(params[:body])
      # binding.irb
      binding.irb
      cc_message.content = body['inputText']
      cc_message.role = 1
      cc_message.sequence = 1
      cc_message.completion_id = 1
      cc_message.is_response = 1

      # ChatCompletionSummary attributes
      cc_summary.api_key_last_four_digits = 1
      cc_summary.request_max_tokens = body['maxTokenCount']
      cc_summary.response_number_of_messages = 1
      cc_summary.request_model = 1
      cc_summary.response_organization = 1
      cc_summary.response_usage_total_tokens = 1
      cc_summary.response_usage_prompt_tokens = 1
      cc_summary.response_usage_completion_tokens = 1
      cc_summary.response_choices_finish_reason = 1
      cc_summary.request_temperature = body['temperature']
      cc_summary.duration = 1
      cc_summary.error = 1


      # record/fininsh events here?
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

  # module BedrockRuntime
  #   def invoke_model_with_new_relic(*args, **kwargs)
  #     # add instrumentation content here
  #     puts "$" * 100
  #     puts "runtime-invoke_model_with_new_relic"
  #     puts args 
  #     puts kwargs
  #     yield
  #   end
  # end
end
