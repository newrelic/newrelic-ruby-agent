# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/event_listener'
require 'new_relic/rack/agent_middleware'
require 'new_relic/agent/instrumentation/middleware_proxy'

module NewRelic::Rack
  # This middleware is used by the agent internally, and is usually injected
  # automatically into the middleware chain. If automatic injection is not
  # working, you may manually use it in your middleware chain instead.
  #
  # @api public
  #
  class AgentHooks < AgentMiddleware
    # We use this key in the Rack env hash to note when we've already fired
    # events for a given request, in case this middleware gets installed
    # multiple times in the middleware chain because of a misconfiguration.
    ENV_KEY = "newrelic.agent_hooks_fired".freeze

    def traced_call(env)
      if env[ENV_KEY]
        # Already fired the hooks, just pass through
        @app.call(env)
      else
        env[ENV_KEY] = true

        events.notify(:before_call, env)
        result = @app.call(env)
        events.notify(:after_call, env, result)

        result
      end
    end

    def events
      NewRelic::Agent.instance.events
    end
  end
end
