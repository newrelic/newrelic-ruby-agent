# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

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
    end

    def subscribe(event, &handler)
      @events[event] ||= []
      @events[event] << handler
      check_for_runaway_subscriptions(event)
    end

    def check_for_runaway_subscriptions(event)
      count = @events[event].size
      if count > @runaway_threshold
        NewRelic::Agent.logger.debug("Run-away event subscription on #{event}? Subscribed #{count}")
      end
    end

    def clear
      @events.clear
    end

    def notify(event, *args)
      return unless @events.has_key?(event)

      @events[event].each do |handler|
        handler.call(*args)
      rescue StandardError => e
        NewRelic::Agent.logger.debug("Failure during notify for #{event}", e)
      end
    end
  end
end
