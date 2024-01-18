# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module OpenAI::Client::Chain
    def self.instrument!
      ::OpenAI::Client.class_eval do
        include NewRelic::Agent::Instrumentation::OpenAI::Client

        alias_method(:method_to_instrument_without_new_relic, :method_to_instrument)
        alias_method(:method_to_instrument, :method_to_instrument_with_new_relic)

        def method_to_instrument(*args)
          method_to_instrument_with_new_relic(*args) do
            method_to_instrument_without_new_relic(*args)
          end
        end
      end
    end
  end
end
