# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module GrapeInstrumentation
      API_ENDPOINT = 'api.endpoint'.freeze
      FORMAT       = '(.:format)'.freeze
      EMPTY_STRING = ''.freeze
      MIN_VERSION  = ::NewRelic::VersionNumber.new("0.2.0")
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
    false
  end

  executes do
    NewRelic::Agent.logger.info 'Installing Grape instrumentation'
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
              route_obj = endpoint.route
              if route_obj
                action_name = route_obj.route_path.sub(::NewRelic::Agent::GrapeInstrumentation::FORMAT,
                                                        ::NewRelic::Agent::GrapeInstrumentation::EMPTY_STRING)
                method_name = route_obj.route_method

                txn_name = "#{self.class.name}#{action_name} (#{method_name})"
                ::NewRelic::Agent.set_transaction_name(txn_name)
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
