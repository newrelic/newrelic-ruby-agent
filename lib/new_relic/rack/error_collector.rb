# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/rack/agent_middleware'
require 'new_relic/agent/instrumentation/middleware_proxy'

module NewRelic::Rack
  # This middleware is used by the agent in order to capture exceptions that
  # occur within your web application. It will normally be injected into the
  # middleware chain automatically, but if automatic injection fails in your
  # environment, you may alternately include it manually.
  #
  # @api public
  #
  class ErrorCollector < AgentMiddleware
    def params_from_env(env)
      if defined?(ActionDispatch::Request)
        # We use ActionDispatch::Request if it's available so that we can get
        # the parameter filtering supplied by Rails via filtered_parameters.
        # The action and controller params are synthesized by
        # ActionDispatch::Request, so we strip them for consistency with Rack::Request
        params = ActionDispatch::Request.new(env).filtered_parameters
        params.delete('action')
        params.delete('controller')
        params
      else
        Rack::Request.new(env).params
      end
    rescue => e
      warning = "failed to capture request parameters: %p: %s" % [ e.class, e.message ]
      NewRelic::Agent.logger.warn(warning)
      { 'error' => warning }
    end

    def strip_query_string(s)
      s.gsub(/\?.*/, '')
    end

    def uri_from_env(env)
      strip_query_string("#{env['SCRIPT_NAME']}#{env['PATH_INFO']}")
    end

    def referrer_from_env(env)
      strip_query_string(env['HTTP_REFERER'].to_s)
    end

    def traced_call(env)
      begin
        @app.call(env)
      rescue Exception => exception
        NewRelic::Agent.logger.debug "collecting %p: %s" % [ exception.class, exception.message ]
        if !should_ignore_error?(exception, env)
          NewRelic::Agent.notice_error(exception,
                                       :uri => uri_from_env(env),
                                       :referer => referrer_from_env(env),
                                       :request_params => params_from_env(env))
        end
        raise exception
      end
    end

    def should_ignore_error?(error, env)
      NewRelic::Agent.instance.error_collector.error_is_ignored?(error)
    end
  end
end
