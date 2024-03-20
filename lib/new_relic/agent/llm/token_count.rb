# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Llm
      module TokenCount
        def call_token_count_callback(model, content)
          return unless NewRelic::Agent.llm_token_count_callback
          
          count = NewRelic::Agent.llm_token_count_callback.call({model: model, content: content})
          self.token_count = count if count.is_a?(Integer) && count > 0
        end
      end
    end
  end
end
