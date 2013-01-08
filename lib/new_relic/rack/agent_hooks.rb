require 'new_relic/agent/event_listener'

module NewRelic::Rack
  class AgentHooks
    def initialize(app, options = {})
      @app = app
    end

    # Track events at the class level, so expected to only be relatively
    # static (agent-singleton style) objects that subscribe, not per request!
    @@events = NewRelic::Agent::EventListener.new(AgentHooks)

    # method required by Rack interface
    # [status, headers, response]
    def call(env)
      @@events.notify :before_call, env
      result = @app.call(env)
      @@events.notify :after_call, env, result
      result
    end

    def self.subscribe(event, &handler)
      @@events.subscribe(event, &handler)
    end
  end
end

