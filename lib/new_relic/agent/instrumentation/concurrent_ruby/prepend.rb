# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module ConcurrentRuby::Prepend
    include NewRelic::Agent::Instrumentation::ConcurrentRuby

    def future(*args, &task)
      future_with_new_relic(*args) { super }
    end
  end
end
