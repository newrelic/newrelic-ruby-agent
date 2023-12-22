# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module ViewComponent::Chain
    def self.instrument!
      ::ViewComponent::Base.class_eval do
        include NewRelic::Agent::Instrumentation::ViewComponent

        alias_method(:render_in_without_tracing, :render_in)

        def render_in(*args)
          render_in_with_tracing(*args) do
            render_in_without_tracing(*args)
          end
        end
      end
    end
  end
end
