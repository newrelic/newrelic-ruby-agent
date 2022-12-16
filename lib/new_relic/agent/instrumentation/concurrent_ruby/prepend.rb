# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module ConcurrentRuby::Prepend
    include NewRelic::Agent::Instrumentation::ConcurrentRuby

    def post(*args, &task)
      traced_task = add_task_tracing(*args, &task)
      post_with_new_relic(*args) { super(*args, &traced_task) }
    end
  end
end
