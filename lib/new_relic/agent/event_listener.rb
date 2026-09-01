# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  # Basic mechanism for the agent instance to provide agent-wide eventing.
  # It is intended to keep different pieces of the app decoupled from each other.
  #
  # While an EventListener could be used elsewhere, it's strongly expected
  # your eventing needs should be met by the agent's instance.
  class EventListener
    attr_accessor :runaway_threshold

    def initialize
      @events = {}
      @runaway_threshold = 100
      @write_lock = Mutex.new
    end

    # Copy-on-write: replaces @events[event] rather than mutating it, so a #notify already
    # iterating the old array on another thread isn't disrupted by a concurrent subscribe.
    # @write_lock serializes subscribe/unsubscribe against each other -- without it, two
    # concurrent writers racing this read-modify-write can each build a copy from the same
    # stale array, and the second assignment silently discards the other's change.
    def subscribe(event, &handler)
      @write_lock.synchronize { @events[event] = (@events[event] || []) + [handler] }
      check_for_runaway_subscriptions(event)
      handler
    end

    def unsubscribe(event, handler)
      @write_lock.synchronize do
        return unless @events[event]

        @events[event] -= [handler]
      end
    end

    def check_for_runaway_subscriptions(event)
      count = @events[event].size
      NewRelic::Agent.logger.debug("Run-away event subscription on #{event}? Subscribed #{count}") if count > @runaway_threshold
    end

    def clear
      @events.clear
    end

    def notify(event, *args)
      return unless @events.has_key?(event)

      @events[event].each do |handler|
        begin
          handler.call(*args)
        rescue => err
          NewRelic::Agent.logger.debug("Failure during notify for #{event}", err)
        end
      end
    end
  end
end
