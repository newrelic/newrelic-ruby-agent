# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module ConcurrentRuby
    def self.instrument!
      # this is a module, can I still use class_eval?
      ::Concurrent::Promises::FactoryMethods.class_eval do
        include NewRelic::Agent::Instrumentation::ConcurrentRuby

        alias_method(:future_without_new_relic, :future)
        alias_method(:future, :future_with_new_relic)

        def future(*args, &task)
          future_with_new_relic(*args) do
            future_without_new_relic(*args, &task)
          end
        end
      end
    end
  end
end
