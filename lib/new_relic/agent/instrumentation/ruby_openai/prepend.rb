# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module OpenAI::Prepend
    include NewRelic::Agent::Instrumentation::OpenAI

    # In versions 4.0.0+ json_post is an instance method defined in the
    # OpenAI::HTTP module, included by the OpenAI::Client class.
    #
    # In versions 3.0.3 - 3.7.0 json_post is a class method on OpenAI::Client.
    #
    # Dependency detection will apply the instrumentation to the correct scope,
    # so we don't need to change the code here.
    def json_post(**kwargs)
      json_post_with_new_relic(**kwargs) { super }
    end
  end
end
