# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/event_listener'

module NewRelic::Rack
  # This middleware is used by the agent internally, and is usually injected
  # automatically into the middleware chain. If automatic injection is not
  # working, you may manually use it in your middleware chain instead.
  #
  # @api public
  #
  class AgentHooks
    def initialize(app, options = {})
      @app = app
    end

    FIRED_FORMATS = {
      :before_call => "newrelic.agent_hooks_before_fired",
      :after_call  => "newrelic.agent_hooks_after_fired"
    }

    # method required by Rack interface
    # [status, headers, response]
    def call(env)
      notify(:before_call, env)
      result = @app.call(env)
      notify(:after_call, env, result)
      result
    end

    def notify(event, env, *args)
      key = FIRED_FORMATS[event]
      events.notify(event, *([env] + args)) unless env[key]
      env[key] = true
    end

    def events
      NewRelic::Agent.instance.events
    end
  end
end
