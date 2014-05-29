# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/instrumentation/rack_middleware'

DependencyDetection.defer do
  named :rails_middleware

  depends_on do
    defined?(::Rails) && ::Rails::VERSION::MAJOR.to_i >= 3
  end

  executes do
    module ActionDispatch
      class MiddlewareStack
        class Middleware
          def build_with_new_relic(app)
            result = build_without_new_relic(app)
            ::NewRelic::Agent::Instrumentation::RackMiddleware.add_new_relic_tracing_to_middleware(result)
            result
          end

          alias_method :build_without_new_relic, :build
          alias_method :build, :build_with_new_relic
        end
      end
    end
  end
end
