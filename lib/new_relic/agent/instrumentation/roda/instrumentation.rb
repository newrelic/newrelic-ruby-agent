# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Roda
    module Tracer
      include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation

      def self.included(clazz)
        clazz.extend(self)
      end

      def newrelic_middlewares
        middlewares = [NewRelic::Rack::BrowserMonitoring]
        if NewRelic::Rack::AgentHooks.needed?
          middlewares << NewRelic::Rack::AgentHooks
        end
        middlewares
      end

      def build_rack_app_with_tracing
        unless NewRelic::Agent.config[:disable_roda_auto_middleware]
          newrelic_middlewares.each do |middleware_class|
            self.use middleware_class
          end
        end
        yield
      end

      # Roda makes use of Rack, so we can get params from the request object
      def rack_request_params
        begin
          @_request.params
        rescue => e
          NewRelic::Agent.logger.debug('Failed to get params from Rack request.', e)
          nil
        end
      end

      def _roda_handle_main_route_with_tracing(*args)
        request_params = rack_request_params
        filtered_params = ::NewRelic::Agent::ParameterFiltering::apply_filters(request.env, request_params ||
          NewRelic::EMPTY_HASH)
        name = TransactionNamer.initial_transaction_name(request)

        perform_action_with_newrelic_trace(:category => :roda,
          :name => name,
          :params => filtered_params) do
          yield
        end
      end
    end
  end
end
