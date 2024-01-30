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
      puts params
      puts options
      puts result
      @nr_attributes = {}
      ###################
      model = params[:model_id]
      if model.start_with?('amazon.titan-')
        titan_attributes(params, options, result)
      elsif model.start_with?('anthropic.claude-')
        anthropic_attributes(params, options, result)
      elsif model.start_with?('cohere.command-')
        cohere_command_attributes(params, options, result)
        # elsif model.start_with?('cohere.embed-') # ?????
        # cohere_embed_attributes(params, options, result)
      elsif model.start_with?('meta.llama2-')
        llama2_attributes(params, options, result)
      elsif model.start_with?('ai21.j2-')
        jurassic_attributes(params, options, result)

      else
        # unknown model
        'unknown model'
      end
    end

    # adsfv
    def titan_attributes(params, options, result)

    end

    def anthropic_attributes(params, options, result)

    end

    def cohere_command_attributes(params, options, result)

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
