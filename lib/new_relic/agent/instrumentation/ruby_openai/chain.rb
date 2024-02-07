# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module OpenAI::Chain
    def self.instrument!
      ::OpenAI::Client.class_eval do
        include NewRelic::Agent::Instrumentation::OpenAI

        alias_method(:json_post_without_new_relic, :json_post)

        # In versions 4.0.0+ json_post is an instance method
        # defined in the OpenAI::HTTP module, included by the
        # OpenAI::Client class
        def json_post(**kwargs)
          json_post_with_new_relic(**kwargs) do
            json_post_without_new_relic(**kwargs)
          end
        end

        # In versions 3.0.3 - 3.7.0 json_post is a class method
        # on OpenAI::Client
        class << self
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
end
