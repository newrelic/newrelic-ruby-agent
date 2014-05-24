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

            # klass a method on ActionDispatch::MiddlewareStack::Middleware
            # that either returns klass_or_name (if klass_or_name.respond_to?(:name))
            # or treats klass_or_name as a String and tries to constantize it.
            #
            # It turns out you can also pass an *instance* of a middleware to
            # initialize and still have it work. How? Terrible magic: define an
            # *instance* method called new that captures its argument
            # (representing the rack layer below you) and returns self, and make
            # sure you respond to name.
            #
            # This is done here in Rails:
            # https://github.com/rails/rails/blob/4-1-stable/activesupport/lib/active_support/cache/strategy/local_cache_middleware.rb#L19-L22
            #
            # So if the thing we get back from klass is not a Class but a
            # middleware class (in practice it seems that
            # ActiveSupport::Cache::Strategy::LocalCache::Middleware is the only
            # actual offender here in Rails), then we patch the singleton class
            # of the instance.
            #
            # We're patching the singleton class of the instance rather than the
            # class directly in case the Class is something super generic like
            # Proc.
            #
            class_to_instrument = if klass.is_a?(Class)
              klass
            else
              # Can't use Object#singleton_class because Ruby 1.8
              class << klass; self; end
            end

            if !class_to_instrument.instance_variable_get(:@_nr_rails_middleware_instrumentation_installed)
              class_to_instrument.class_eval do
                @_nr_rails_middleware_instrumentation_installed = true
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
