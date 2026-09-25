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

    # Copy-on-write, not `<<`, so a #notify iterating the old array is undisturbed; @write_lock
    # stops two writers building copies from the same stale array and discarding each other.
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
