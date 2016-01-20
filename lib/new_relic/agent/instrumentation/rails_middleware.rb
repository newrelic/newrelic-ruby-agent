# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/instrumentation/middleware_proxy'

DependencyDetection.defer do
  named :rails_middleware

  depends_on do
    defined?(::Rails) && ::Rails::VERSION::MAJOR.to_i >= 3
  end

  depends_on do
    !::NewRelic::Agent.config[:disable_middleware_instrumentation]
  end

  executes do
    ::NewRelic::Agent.logger.info("Installing Rails 3+ middleware instrumentation")
    module ActionDispatch
      class MiddlewareStack
        class Middleware
          prepend Module.new do
            def build_with_new_relic(app)
              # MiddlewareProxy.wrap guards against double-wrapping here.
              # We need to instrument the innermost app (usually a RouteSet),
              # which will never itself be the return value from #build, but will
              # instead be the initial value of the app argument.
              wrapped_app = ::NewRelic::Agent::Instrumentation::MiddlewareProxy.wrap(app)
              result = super(wrapped_app)
              ::NewRelic::Agent::Instrumentation::MiddlewareProxy.wrap(result)
            end
          end
        end
      end
    end
  end
end
