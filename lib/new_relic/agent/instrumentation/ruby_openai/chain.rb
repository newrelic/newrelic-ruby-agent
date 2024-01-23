# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module OpenAI::Chain
    def self.instrument!
      ::OpenAI::Client.class_eval do
        include NewRelic::Agent::Instrumentation::OpenAI

        alias_method(:json_post_without_new_relic, :json_post)

        def json_post(**kwargs)
          json_post_with_new_relic(**kwargs) do
            json_post_without_new_relic(**kwargs)
          end
        end
      end
    end
  end
end
