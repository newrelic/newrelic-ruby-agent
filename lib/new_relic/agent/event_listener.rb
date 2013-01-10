module NewRelic::Agent
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
      NewRelic::Agent.logger.debug("Run-away event subscription on #{event}? Subscribed #{count}") if count > @runaway_threshold
    end

    def notify(event, *args)
      return unless @events.has_key?(event)

      @events[event].each do |handler|
        begin
          handler.call(*args)
        rescue => err
          NewRelic::Agent.logger.debug("Failure during notify for #{@event}", err)
        end
      end
    end
  end
end
