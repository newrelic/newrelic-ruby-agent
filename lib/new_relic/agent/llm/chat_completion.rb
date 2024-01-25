# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Llm
      module ChatCompletion
        ATTRIBUTES = %i[conversation_id]

        attr_accessor(*ATTRIBUTES)
      end
    end
  end
end
