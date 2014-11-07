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
    instrument_call
  end

  def instrument_call
    ::Grape::API.class_eval do
      def call_with_new_relic(env)
        begin
          response = call_without_new_relic(env)
        rescue Exception => e
          exception = e
        end

        endpoint = env['api.endpoint']

        if endpoint
          route_obj   = endpoint.params['route_info']
          action_name = route_obj.route_path.gsub('(.:format)','')
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
