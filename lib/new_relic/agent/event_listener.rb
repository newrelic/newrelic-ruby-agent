# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic::Agent
  # Basic mechanism for the agent instance to provide agent-wide eventing.
  # It is intended to keep different pieces of the app decoupled from each other.
  #
  # While an EventListener could be used elsewhere, it's strongly expected
  # your eventing needs should be met by the agent's instance.
  class EventListener

    class NotifyHandler
      attr_reader :listener
      attr_reader :event
      attr_reader :handler

      def initialize listener, event, &handler
        @listener = listener
        @event = event
        @handler = handler
      end

      def unsubscribe
        @listener.unsubscribe event, self
      end

      def call(*args)
        @handler.call(*args)
      rescue => err
        NewRelic::Agent.logger.debug("Failure during notify for #{event}", err)
      end
    end

    attr_accessor :runaway_threshold

    def initialize
      @events = {}
      @runaway_threshold = 100
    end

    def subscribe(event, &handler)
      @events[event] ||= []
      notifier = NotifyHandler.new(self, event, &handler)
      @events[event] << notifier
      check_for_runaway_subscriptions(event)
      return notifier
    end

    def unsubscribe event, handler
      return unless @events.has_key?(event)
      @events[event].reject!{|h| h == handler}
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
      @events[event].each{ |handler| handler.call(*args) }
    end
  end
end
