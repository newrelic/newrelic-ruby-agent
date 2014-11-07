# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  named :grape

  depends_on do
    defined?(::Grape) && defined?(::Grape::API)
  end

  executes do
    NewRelic::Agent.logger.info 'Installing Grape instrumentation'
    install_grape_instrumentation
  end

  def install_grape_instrumentation
    install_constants
    instrument_call
  end

  def install_constants
    grape_constants = Module.new

    grape_constants.const_set(:API_ENDPOINT, 'api.endpoint'.freeze)
    grape_constants.const_set(:ROUTE_INFO  ,   'route_info'.freeze)
    grape_constants.const_set(:FORMAT      ,   '(.:format)'.freeze)
    grape_constants.const_set(:EMPTY_STRING,             ''.freeze)

    ::NewRelic::Agent.const_set(:GrapeConstants, grape_constants)
  end

  def instrument_call
    ::Grape::API.class_eval do
      def call_with_new_relic(env)
        begin
          response = call_without_new_relic(env)
        rescue Exception => e
          exception = e
        end

        endpoint = env[::NewRelic::Agent::GrapeConstants::API_ENDPOINT]

        if endpoint
          route_obj   = endpoint.params[::NewRelic::Agent::GrapeConstants::ROUTE_INFO]
          action_name = route_obj.route_path.gsub(::NewRelic::Agent::GrapeConstants::FORMAT,
                                                  ::NewRelic::Agent::GrapeConstants::EMPTY_STRING)
          method_name = route_obj.route_method

          txn_name = "#{self.class.name}#{action_name} (#{method_name})"
          ::NewRelic::Agent.set_transaction_name(txn_name)
        end

        raise exception if exception

        response
      end

      alias_method :call_without_new_relic, :call
      alias_method :call, :call_with_new_relic
    end
  end

end
