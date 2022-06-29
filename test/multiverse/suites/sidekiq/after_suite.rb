# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module Sidekiq
  class CLI
    def exit(*args)
      # No-op Sidekiq's exit since we don't want it shutting us down and eating
      # our exit code
    end
  end
end

if defined?(SidekiqServer)
  SidekiqServer.instance.stop
end
