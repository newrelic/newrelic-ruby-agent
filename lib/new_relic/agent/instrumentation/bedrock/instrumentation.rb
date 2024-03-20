# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Bedrock
    def invoke_model_with_new_relic(params, options)
      @nr_events = [] # tmp

      NewRelic::Agent.record_metric("Supportability/Ruby/ML/Bedrock/#{Aws::BedrockRuntime::GEM_VERSION}", 0.0)
      NewRelic::Agent::Llm::LlmEvent.set_llm_agent_attribute_on_transaction

      segment_name = "Llm/#{is_embed_model?(params[:model_id]) ? 'Embedding' : 'Completion'}/Bedrock/invoke_model"
      segment = NewRelic::Agent::Tracer.start_segment(name: segment_name)
      segment.llm_event = {} if segment

      response = NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
    ensure
      segment&.finish
      create_llm_events(segment, params, response)
      # binding.irb
    end

    ##################################################################

    def create_llm_events(segment, params, response)
      model, body, response_body = json_parse_params(params, response)
      shared_attributes = create_shared_attributes(model, segment)

      if is_embed_model?(model)
        create_embed_event(model, body, response_body, shared_attributes, segment)
      else
        create_chat_completion_events(model, body, response_body, shared_attributes, segment)
      end
    rescue => e
      # log something
      puts 'oop'
      puts e
      puts e.backtrace
    end

    def is_embed_model?(model)
      model.start_with?('amazon.titan-embed-', 'cohere.embed-')
    end

    ##################################################################

    def create_chat_completion_events(model, body, response_body, shared_attributes, segment)
      summary_attributes, messages_attributes = if model.start_with?('amazon.titan-text-')
        titan_attributes(body, response_body)
      elsif model.start_with?('anthropic.claude-')
        anthropic_attributes(body, response_body)
      elsif model.start_with?('cohere.command-')
        cohere_command_attributes(body, response_body)
      elsif model.start_with?('meta.llama2-')
        llama2_attributes(body, response_body)
      elsif model.start_with?('ai21.j2-')
        ajurassic_attributes(body, response_body)
      else
        # log something?
        return
      end

      summary_event = create_chat_completion_summary_event(shared_attributes, summary_attributes, segment)
      messages_attributes.each_with_index do |message, index|
        create_chat_completion_message_event(index, summary_event.id, shared_attributes, message)
      end
    end

    def create_chat_completion_summary_event(shared, attributes, segment)
      summary_event = NewRelic::Agent::Llm::ChatCompletionSummary.new(shared)

      @nr_events << summary_event # TODO: tmp

      summary_event.id = NewRelic::Agent::GuidGenerator.generate_guid
      summary_event.request_model = shared[:response_model]
      summary_event.response_number_of_messages = attributes[:response_number_of_messages]
      summary_event.request_temperature = attributes[:request_temperature]

      summary_event.request_max_tokens = attributes[:request_max_tokens]
      # summary_event.response_usage_prompt_tokens = segment&.llm_event&.[](:response_usage_prompt_tokens)&.to_i
      # summary_event.response_usage_completion_tokens = segment&.llm_event&.[](:response_usage_completion_tokens)&.to_i
      # summary_event.response_usage_total_tokens = summary_event.response_usage_prompt_tokens + summary_event.response_usage_completion_tokens

      summary_event.response_choices_finish_reason = attributes[:response_choices_finish_reason]
      summary_event.duration = segment&.duration
      summary_event.error = true if segment&.noticed_error

      summary_event.record

      summary_event
    end

    def create_chat_completion_message_event(index, completion_id, shared, attributes)
      message_event = NewRelic::Agent::Llm::ChatCompletionMessage.new(shared)
      @nr_events << message_event # TODO: tmp
      message_event.id = "#{shared[:request_id]}-#{index}"
      message_event.completion_id = completion_id
      message_event.sequence = index
      message_event.content = attributes[:content]
      message_event.role = attributes[:role]
      message_event.is_response = attributes[:is_response] if attributes[:is_response]
      message_event.token_count = get_token_count(shared[:response_model], message_event.content)

      message_event.record
    end

    def get_token_count(model, content)
      return unless NewRelic::Agent.llm_token_count_callback

      count = NewRelic::Agent.llm_token_count_callback.call({model: model, content: content})
      count if count.is_a?(Integer) && count > 0
    end

    ##################################################################

    def create_embed_event(model, body, response_body, shared_attributes, segment)
      embed_attributes = if model.start_with?('amazon.titan-embed-')
        # titan_embed_attributes(body, response_body)
        {input: body['inputText']}
      elsif model.start_with?('cohere.embed-')
        {input: body['text']}
      end

      embed_event = NewRelic::Agent::Llm::Embedding.new(shared_attributes)

      embed_event.input = embed_attributes[:input]
      embed_event.request_model = shared_attributes[:response_model]
      embed_event.duration = segment&.duration
      embed_event.error = true if segment&.noticed_error

      embed_event.token_count = get_token_count(model, embed_event.input)

      @nr_events << embed_event # TODO: tmp

      embed_event.record
    end

    ##################################################################

    def create_shared_attributes(model, segment)
      shared_attributes = {}

      shared_attributes[:request_id] = segment&.llm_event&.[](:request_id)
      shared_attributes[:response_model] = model
      shared_attributes[:vendor] = 'bedrock'
      shared_attributes[:metadata] = llm_custom_attributes

      shared_attributes
    end

    def json_parse_params(params, response)
      model = params[:model_id]
      body = JSON.parse(params[:body])
      response_body = JSON.parse(response.body.read)
      response.body.rewind # put the response back

      return model, body, response_body
    end

    def llm_custom_attributes
      attributes = NewRelic::Agent::Tracer.current_transaction&.attributes&.custom_attributes&.select { |k| k.to_s.match(/llm.*/) }

      attributes&.transform_keys! { |key| key[4..-1] }
    end

    ##################################################################
    # Model attributes
    ##################################################################
    def titan_attributes(body, response_body)
      summary_attributes = {}

      summary_attributes[:request_max_tokens] = body['textGenerationConfig']['maxTokenCount']
      summary_attributes[:response_number_of_messages] = 1 + response_body['results'].length
      summary_attributes[:request_temperature] = body['textGenerationConfig']['temperature']
      summary_attributes[:response_choices_finish_reason] = response_body['results'][0]['completionReason']

      messages_attributes = []

      messages_attributes << {
        content: body['inputText'],
        role: 'user'
      }

      response_body['results'].each do |result|
        messages_attributes << {
          content: result['outputText'],
          role: 'assistant',
          is_response: true
        }
      end

      return summary_attributes, messages_attributes
    end

    def anthropic_attributes(body, response_body)
      summary_attributes = {}

      summary_attributes[:request_max_tokens] = body['max_tokens_to_sample']
      summary_attributes[:response_number_of_messages] = 2
      summary_attributes[:request_temperature] = body['temperature']
      summary_attributes[:response_choices_finish_reason] = response_body['stop_reason']

      messages_attributes = []

      messages_attributes << {
        content: body['prompt'],
        role: 'user'
      }

      messages_attributes << {
        content: response_body['completion'],
        role: 'assistant',
        is_response: true
      }

      return summary_attributes, messages_attributes
    end

    def cohere_command_attributes(body, response_body)
      summary_attributes = {}

      summary_attributes[:request_max_tokens] = body['max_tokens']
      summary_attributes[:response_number_of_messages] = 1 + response_body['generations'].length
      summary_attributes[:request_temperature] = body['temperature']
      summary_attributes[:response_choices_finish_reason] = response_body['generations'][0]['finish_reason']

      messages_attributes = []

      messages_attributes << {
        content: body['prompt'],
        role: 'user'
      }

      response_body['generations'].each do |result|
        messages_attributes << {
          content: result['text'],
          role: 'assistant',
          is_response: true
        }
      end

      return summary_attributes, messages_attributes
    end

    def llama2_attributes(body, response_body)
      summary_attributes = {}

      summary_attributes[:request_max_tokens] = body['max_gen_len']
      summary_attributes[:response_number_of_messages] = 2
      summary_attributes[:request_temperature] = body['temperature']
      summary_attributes[:response_choices_finish_reason] = response_body['stop_reason']

      messages_attributes = []

      messages_attributes << {
        content: body['prompt'],
        role: 'user'
      }

      messages_attributes << {
        content: response_body['generation'],
        role: 'assistant',
        is_response: true
      }

      return summary_attributes, messages_attributes
    end

    def jurassic_attributes(body, response_body)
      summary_attributes = {}

      summary_attributes[:request_max_tokens] = body['maxTokens']
      summary_attributes[:response_number_of_messages] = 1 + response_body['completions'].length
      summary_attributes[:request_temperature] = body['temperature']
      summary_attributes[:response_choices_finish_reason] = response_body['completions'][0]['finishReason']['reason']

      messages_attributes = []

      messages_attributes << {
        content: body['prompt'],
        role: 'user'
      }

      response_body['completions'].each do |result|
        messages_attributes << {
          content: result['data']['text'],
          role: 'assistant',
          is_response: true
        }
      end

      return summary_attributes, messages_attributes
    end
  end
end
