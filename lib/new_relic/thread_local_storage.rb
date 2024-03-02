# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module ThreadLocalStorage
    def self.get(thread, key)
      if Agent.config[:thread_local_tracer_state]
        thread.thread_variable_get(key)
      else
        thread[key]
      end
    end

    def self.set(thread, key, value)
      if Agent.config[:thread_local_tracer_state]
        thread.thread_variable_set(key, value)
      else
        thread[key] = value
      end
    end

    def self.[](key)
      get(::Thread.current, key)
    end

    def self.[]=(key, value)
      set(::Thread.current, key, value)
    end
  end
end
