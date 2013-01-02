require 'rack'

module NewRelic::Rack
  class AgentHooks

    def initialize(app, options = {})
      @app = app
      @events = {}
    end

    # method required by Rack interface
    # [status, headers, response]
    def call(env)
      notify :before_call, env
      result = @app.call(env)
      notify :after_call, env, result
      result
    end

    def subscribe(event, &handler)
      @events[event] = [] unless @events.has_key?(event)
      @events[event] << handler
    end

    def notify(event, *args)
      return unless @events.has_key?(event)

      @events[event].each do |e|
        e.call(*args)
      end
    end

  end
end

