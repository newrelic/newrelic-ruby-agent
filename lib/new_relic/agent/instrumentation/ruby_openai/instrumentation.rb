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
      elsif path == CHAT_COMPLETIONS_PATH
        # chat_completions_instrumentation(parameters, headers)
        segment = NewRelic::Agent::Tracer.start_segment(name: 'Llm/completion/OpenAI/create')
        event = NewRelic::Agent::LlmEvent::ChatCompletion::Summary.new
        segment.instance_variable_set(:@llm_summary, event)
        begin
          NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
        ensure
          segment&.finish
          event.record
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

    # def chat_completions_instrumentation(parameters, request_headers)
    #   # TBD
    #   segment = NewRelic::Agent::Tracer.start_segment(name: 'Llm/completion/OpenAI/create')
    #   begin
    #     NewRelic::Agent::Tracer.capture_segment_error(segment) { super }
    #   ensure
    #     segment&.finish
    #   end
    # end
  end
end
