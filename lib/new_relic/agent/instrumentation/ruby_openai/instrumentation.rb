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
      if path == EMBEDDINGS_PATH
        embeddings_instrumentation(parameters, headers)
      elsif path == CHAT_COMPLETIONS_PATH
        chat_completions_instrumentation(parameters, headers)
      else
        yield
      end
    end

    private

    def embeddings_instrumentation(parameters, request_headers)
      # TBD
      yield
    end

    def chat_completions_instrumentation(parameters, request_headers)
      # TBD
      yield
    end
  end
end
