# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic::Agent::Instrumentation
  module Tilt
    def self.instrument!
      ::Tilt::Template.module_eval do
        include NewRelic::Agent::Instrumentation::Tilt

        def initialize_with_new_relic(*args, &block)
          initialize_with_tracing(*args) {
            initialize_without_newrelic(*args, &block)
          }
        end

        alias initialize_without_newrelic initialize
        alias initialize initialize_with_new_relic
      end
    end
  end
end
