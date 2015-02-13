# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/rack/agent_middleware'

module NewRelic::Rack
  # This middleware is no longer used by the agent by default, but remains here
  # for API compatibility purposes.
  #
  # You should remove any references to it from your config.ru or other rack
  # middleware configuration files.
  #
  # The agent will instead now automatically collect errors for all Rack
  # applications if automatic Rack middleware instrumentation is enabled (it is
  # by default), or if you have manually added any New Relic middlewares into
  # your middleware stack.
  #
  # @api public
  # @deprecated
  #
  class ErrorCollector < AgentMiddleware
    def traced_call(env)
      @app.call(env)
    end
  end
end
