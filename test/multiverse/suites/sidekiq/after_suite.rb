# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

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
