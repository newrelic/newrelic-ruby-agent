# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module ThreadLocalStorage
    def self.get(thread, key)
      thread[key]
    end

    def self.set(thread, key, value)
      thread[key] = value
    end

    def self.[](key)
      get(::Thread.current, key)
    end

    def self.[]=(key, value)
      set(::Thread.current, key, value)
    end
  end
end
