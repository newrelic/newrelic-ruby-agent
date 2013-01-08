module NewRelic::Rack
  class AgentHooks

    # Track events at the class level, so expected to only be relatively
    # static (agent-singleton style) objects that subscribe, not per request!
    @@events = {}

    def initialize(app, options = {})
      @app = app
    end

    # method required by Rack interface
    # [status, headers, response]
    def call(env)
      notify :before_call, env
      result = @app.call(env)
      notify :after_call, env, result
      result
    end

    def self.subscribe(event, &handler)
      @@events[event] ||= []
      @@events[event] << handler
      check_for_runaway_subscriptions(event)
    end

    def self.check_for_runaway_subscriptions(event)
      count = @@events[event].size
      NewRelic::Agent.logger.debug("Run-away event subscription on AgentHooks #{event}? Subscribed #{count}") if count > 100
    end

    def notify(event, *args)
      return unless @@events.has_key?(event)

      @@events[event].each do |e|
        begin
          e.call(*args)
        rescue => e
          NewRelic::Agent.logger.debug("Failure during AgentHooks.notify", e)
        end
      end
    end

  end
end

