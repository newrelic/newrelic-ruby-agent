# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/parameter_filtering'

module NewRelic
  module Agent
    module Instrumentation
      module GrapeInstrumentation
        extend self

        API_ENDPOINT   = 'api.endpoint'.freeze
        FORMAT_REGEX   = /\(\/?\.[\:\w]*\)/.freeze # either :format (< 0.12.0) or .ext (>= 0.12.0)
        VERSION_REGEX  = /:version(\/|$)/.freeze
        EMPTY_STRING   = ''.freeze
        MIN_VERSION    = VersionNumber.new("0.2.0")

        def handle_transaction(endpoint, class_name)
          return unless endpoint && route = endpoint.route
          name_transaction(route, class_name)
          capture_params(endpoint)
        end

        def name_transaction(route, class_name)
          txn_name = name_for_transaction(route, class_name)
          node_name = "Middleware/Grape/#{class_name}/call"
          Transaction.set_default_transaction_name(txn_name, :grape, node_name)
        end

        if defined?(Grape::VERSION) && VersionNumber.new(::Grape::VERSION) >= VersionNumber.new("0.16.0")
          def name_for_transaction(route, class_name)
            action_name = route.path.sub(FORMAT_REGEX, EMPTY_STRING)
            method_name = route.request_method

            if route.version
              action_name = action_name.sub(VERSION_REGEX, EMPTY_STRING)
              "#{class_name}-#{route.version}#{action_name} (#{method_name})"
            else
              "#{class_name}#{action_name} (#{method_name})"
            end
          end
        else
          def name_for_transaction(route, class_name)
            action_name = route.route_path.sub(FORMAT_REGEX, EMPTY_STRING)
            method_name = route.route_method

            if route.route_version
              action_name = action_name.sub(VERSION_REGEX, EMPTY_STRING)
              "#{class_name}-#{route.route_version}#{action_name} (#{method_name})"
            else
              "#{class_name}#{action_name} (#{method_name})"
            end
          end
        end

        def capture_params(endpoint)
          txn = Transaction.tl_current
          env = endpoint.request.env
          params = ParameterFiltering::apply_filters(env, endpoint.params)
          params.delete("route_info")
          txn.filtered_params = params
          txn.merge_request_parameters(params)
        end
      end
    end
  end
end

DependencyDetection.defer do
  # Why not just :grape? newrelic-grape used that name already, and while we're
  # not shipping yet, overloading the name interferes with the plugin.
  named :grape_instrumentation

  depends_on do
    ::NewRelic::Agent.config[:disable_grape] == false
  end

  depends_on do
    defined?(::Grape::VERSION) &&
      ::NewRelic::VersionNumber.new(::Grape::VERSION) >= ::NewRelic::Agent::Instrumentation::GrapeInstrumentation::MIN_VERSION
  end

  depends_on do
    begin
      if defined?(Bundler) && Bundler.rubygems.all_specs.map(&:name).include?("newrelic-grape")
        ::NewRelic::Agent.logger.info("Not installing New Relic supported Grape instrumentation because the third party newrelic-grape gem is present")
        false
      else
        true
      end
    rescue => e
      ::NewRelic::Agent.logger.info("Could not determine if third party newrelic-grape gem is installed", e)
      true
    end
  end

  executes do
    NewRelic::Agent.logger.info 'Installing New Relic supported Grape instrumentation'
    instrument_call
  end

  def instrument_call
    ::Grape::API.class_eval do
      def call_with_new_relic(env)
        begin
          response = call_without_new_relic(env)
        ensure
          begin
            endpoint = env[::NewRelic::Agent::Instrumentation::GrapeInstrumentation::API_ENDPOINT]
            ::NewRelic::Agent::Instrumentation::GrapeInstrumentation.handle_transaction(endpoint, self.class.name)
          rescue => e
            ::NewRelic::Agent.logger.warn("Error in Grape instrumentation", e)
          end
        end

        response
      end

      alias_method :call_without_new_relic, :call
      alias_method :call, :call_with_new_relic
    end
  end

end
