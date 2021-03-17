# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic::Agent::Instrumentation
  module Sinatraa
    module Prepend 
      

      def get_request_params
        begin
          @request.params
        rescue => e
          NewRelic::Agent.logger.debug("Failed to get params from Rack request.", e)
          nil
        end
      end

      def dispatch
        request_params = get_request_params
        filtered_params = ParameterFiltering::apply_filters(request.env, request_params || {})

        name = TransactionNamer.initial_transaction_name(request)
        perform_action_with_newrelic_trace(:category => :sinatra,
                                           :name => name,
                                           :params => filtered_params) do
          begin
            super
          ensure
            # Will only see an error raised if :show_exceptions is true, but
            # will always see them in the env hash if they occur
            had_error = env.has_key?('sinatra.error')
            ::NewRelic::Agent.notice_error(env['sinatra.error']) if had_error
          end
        end
      end

        # If a transaction name is already set, this call will tromple over it.
        # This is intentional, as typically passing to a separate route is like
        # an entirely separate transaction, so we pick up the new name.
        #
        # If we're ignored, this remains safe, since set_transaction_name
        # care for the gating on the transaction's existence for us.
        def route_eval(*args, &block)
          begin
            txn_name = TransactionNamer.transaction_name_for_route(env, request)
            unless txn_name.nil?
              ::NewRelic::Agent::Transaction.set_default_transaction_name(
                "#{self.class.name}/#{txn_name}", :sinatra)
            end
          rescue => e
            ::NewRelic::Agent.logger.debug("Failed during route_eval to set transaction name", e)
          end

          super
        end

        def process_route(*args, &block)
          begin
            env["newrelic.last_route"] = args[0]
          rescue => e
            ::NewRelic::Agent.logger.debug("Failed determining last route in Sinatra", e)
          end

          super
        end

      
    end

    module PrependBuild
      def newrelic_middlewares
        middlewares = [NewRelic::Rack::BrowserMonitoring]
        if NewRelic::Rack::AgentHooks.needed?
          middlewares << NewRelic::Rack::AgentHooks
        end
        middlewares
      end

      def build(*args, &block)
        unless NewRelic::Agent.config[:disable_sinatra_auto_middleware]
          newrelic_middlewares.each do |middleware_class|
            try_to_use(self, middleware_class)
          end
        end
        super
      end

      def try_to_use(app, clazz)
        has_middleware = app.middleware.any? { |info| info[0] == clazz }
        app.use(clazz) unless has_middleware
      end
    end
  end
end

