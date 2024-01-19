# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class NewRelic
  class Agent
    class LlmEvent
      class ChatCompletion

        attr_accessor 
          :'request.model', 
          :'response.organization', 
          :'response.usage.total_tokens', 
          :'response.usage.prompt_tokens', 
          :'response.usage.completion_tokens',
          :'response.choices.finish_reason',
          :'response.headers.llmVersion',
          :'response.headers.ratelimitLimitRequests',
          :'response.headers.ratelimitLimitTokens',
          :'response.headers.ratelimitResetTokens',
          :'response.headers.ratelimitResetRequests',
          :'response.headers.ratelimitRemainingTokens',
          :'response.headers.ratelimitRemainingRequests',
          :duration,
          :'request.temperature',
          :error



        class Summary < NewRelic::Agent::LlmEvent::ChatCompletion
          
          def initialize
            
          end
    
          def record
    
          end
        end
      end
    end
  end
end