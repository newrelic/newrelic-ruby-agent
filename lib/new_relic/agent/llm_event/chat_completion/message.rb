# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class NewRelic
  class Agent
    class LlmEvent
      class ChatCompletion
        class Message < NewRelic::Agent::LlmEvent::ChatCompletion

          attr_accessor :content, :role, :sequence, :completion_id, :is_response

          def initialize
            
          end
    
          def record
    
          end
        end
      end
    end
  end
end