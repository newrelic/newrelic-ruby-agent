module NewRelic::Agent
  class EventListener
    def initialize(klass)
      @listening_class = klass
      @events = {}
    end

    def subscribe(event, &handler)
      @events[event] ||= []
      @events[event] << handler
      check_for_runaway_subscriptions(event)
    end

    def check_for_runaway_subscriptions(event)
      count = @events[event].size
      NewRelic::Agent.logger.debug("Run-away event subscription on #{@listening_class} #{event}? Subscribed #{count}") if count > 100
    end

    def notify(event, *args)
      return unless @events.has_key?(event)

      @events[event].each do |e|
        begin
          e.call(*args)
        rescue => e
          NewRelic::Agent.logger.debug("Failure during notify for #{@listening_class}", e)
        end
      end
    end
  end
end
