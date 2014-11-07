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
        response = call_without_new_relic(env)

        route_obj     = env['api.endpoint'].params['route_info']
        route_ns      = env['api.endpoint'].namespace

        class_name    = self.class.name
        resource_name = route_ns.split('/')[1]
        method_name   = route_obj.route_method
        action_name   = route_obj.route_path.split('/').last.gsub('(.:format)','')

        txn_name = [class_name, resource_name, method_name, action_name].join('/')
        ::NewRelic::Agent.set_transaction_name(txn_name)

        response
      end

      alias_method :call_without_new_relic, :call
      alias_method :call, :call_with_new_relic
    end
  end

end
