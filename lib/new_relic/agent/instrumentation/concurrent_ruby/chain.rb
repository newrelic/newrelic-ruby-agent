# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module ConcurrentRuby::Chain
    def self.instrument!
      ::Concurrent::ThreadPoolExecutor.class_eval do
        include NewRelic::Agent::Instrumentation::ConcurrentRuby

        alias_method(:post_without_new_relic, :post)
        alias_method(:post, :post_with_new_relic)

        def post(*args, &task)
          traced_task = add_task_tracing(*args, &task)
          post_with_new_relic(*args) { post_without_new_relic(*args, &traced_task) }
        end
      end
    end
  end
end
