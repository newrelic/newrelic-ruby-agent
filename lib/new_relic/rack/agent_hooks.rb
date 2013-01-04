module NewRelic::Rack
  class AgentHooks

    # We track instances of our middleware (although we expect only one in
    # most reasonable cases), since our ctor won't allow us to be  a
    # singleton, and we need to set even subscriptions to all instances.
    @@instances = []

    def initialize(app, options = {})
      @app = app
      @events = {}

      @@instances << self
      NewRelic::Agent.logger.debug("Found #{@@instances.size} instances of AgentHooks middleware") if @@instances.size > 1
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
      @@instances.each {|i| i.subscribe(event, &handler) }
    end

    def subscribe(event, &handler)
      @events[event] = [] unless @events.has_key?(event)
      @events[event] << handler
    end

    def notify(event, *args)
      return unless @events.has_key?(event)

      @events[event].each do |e|
        begin
          e.call(*args)
        rescue => e
          NewRelic::Agent.logger.debug("Failure during AgentHooks.notify", e)
        end
      end
    end

  end
end

