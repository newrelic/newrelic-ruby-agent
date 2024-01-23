# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module OpenAI::Prepend
    include NewRelic::Agent::Instrumentation::OpenAI

    def json_post(**kwargs)
      json_post_with_new_relic(**kwargs)
    end
  end
end
