# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic::Rack
  # This middleware is used by the agent in order to capture exceptions that
  # occur within your web application. It will normally be injected into the
  # middleware chain automatically, but if automatic injection fails in your
  # environment, you may alternately include it manually.
  #
  # @api public
  #
  class ErrorCollector
    def initialize(app, options={})
      @app = app
    end

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

    def call(env)
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

    def should_ignore_error?(error, env)
      NewRelic::Agent.instance.error_collector.error_is_ignored?(error) ||
        ignored_in_controller?(error, env)
    end

    def ignored_in_controller?(exception, env)
      return true if env['newrelic.ignored']

      if env['action_dispatch.request.parameters']
        ignore_actions = newrelic_ignore_for_controller(env['action_dispatch.request.parameters']['controller'])
        action_name = env['action_dispatch.request.parameters']['action']

        case ignore_actions
        when nil; false
        when Hash
          only_actions = Array(ignore_actions[:only])
          except_actions = Array(ignore_actions[:except])
          only_actions.include?(action_name.to_sym) ||
            (except_actions.any? &&
             !except_actions.include?(action_name.to_sym))
        else
          true
        end
      end
    end

    def newrelic_ignore_for_controller(controller_name)
      if controller_name
        controller_constant_name = (controller_name + "_controller").camelize
        if Object.const_defined?(controller_constant_name)
          controller = controller_constant_name.constantize
          controller.instance_variable_get(:@do_not_trace)
        end
      end
    rescue NameError
      nil
    end
  end
end
