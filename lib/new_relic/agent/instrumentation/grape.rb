# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module GrapeInstrumentation
      API_ENDPOINT   = 'api.endpoint'.freeze
      FORMAT         = '(.:format)'.freeze
      VERSION_PREFIX = ':version/'.freeze
      EMPTY_STRING   = ''.freeze
      MIN_VERSION    = ::NewRelic::VersionNumber.new("0.2.0")
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
      ::NewRelic::VersionNumber.new(::Grape::VERSION) >= ::NewRelic::Agent::GrapeInstrumentation::MIN_VERSION
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
      ::NewRelic::Agent.logger.info("Could not determine if third party newrelic-grape gem is installed")
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
          # We don't want an error in our transaction naming to kill the request.
          begin
            endpoint = env[::NewRelic::Agent::GrapeInstrumentation::API_ENDPOINT]

            if endpoint
              route = endpoint.route
              if route
                action_name = route.route_path.sub(::NewRelic::Agent::GrapeInstrumentation::FORMAT,
                                                       ::NewRelic::Agent::GrapeInstrumentation::EMPTY_STRING)

                method_name = route.route_method

                if route.route_version
                  action_name = action_name.sub(::NewRelic::Agent::GrapeInstrumentation::VERSION_PREFIX,
                                                "#{route.route_version}/")
                  txn_name = "#{self.class.name}-#{route.route_version}#{action_name} (#{method_name})"
                else
                  txn_name = "#{self.class.name}#{action_name} (#{method_name})"
                end

                ::NewRelic::Agent::Transaction.set_default_transaction_name(txn_name, :grape)
              end
            end
          rescue => e
            ::NewRelic::Agent.logger.warn("Error in Grape transaction naming", e)
          end
        end

        response
      end

      alias_method :call_without_new_relic, :call
      alias_method :call, :call_with_new_relic
    end
  end

end
