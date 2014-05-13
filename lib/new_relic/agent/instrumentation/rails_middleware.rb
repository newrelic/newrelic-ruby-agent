# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  named :rails_middleware

  depends_on do
    defined?(::Rails) && ::Rails::VERSION::MAJOR.to_i >= 3
  end

  executes do
    module ActionDispatch
      class MiddlewareStack
        class Middleware
          def initialize_with_new_relic(klass_or_name, *args, &block)
            result = initialize_without_new_relic(klass_or_name, *args, &block)

            if klass.is_a?(Class) && !klass.instance_variable_get(:@_nr_rails_middleware_instrumentation_installed)
              klass.instance_variable_set(:@_nr_rails_middleware_instrumentation_installed, true)

              klass.class_eval do
                include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation
                add_transaction_tracer(:call, :category => :rack, :request => '::Rack::Request.new(args.first)')
              end
            end

            result
          end
          alias_method :initialize_without_new_relic, :initialize
          alias_method :initialize, :initialize_with_new_relic
        end
      end
    end
  end
end
