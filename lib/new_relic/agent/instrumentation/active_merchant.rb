# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  @name = :active_merchant

  depends_on do
    defined?(ActiveMerchant) && defined?(ActiveMerchant::Billing) &&
      defined?(ActiveMerchant::Billing::Gateway) &&
      ActiveMerchant::Billing::Gateway.respond_to?(:implementations)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing ActiveMerchant instrumentation'
  end

  executes do
    class ActiveMerchant::Billing::Gateway
      include NewRelic::Agent::MethodTracer
    end

    ActiveMerchant::Billing::Gateway.implementations.each do |gateway|
      gateway.class_eval do
        implemented_methods = public_instance_methods(false).map(&:to_sym)
        gateway_name = self.name.split('::').last
        [:authorize, :purchase, :credit, :void, :capture, :recurring, :store, :unstore, :update].each do |operation|
          if implemented_methods.include?(operation)
            add_method_tracer operation, "ActiveMerchant/gateway/#{gateway_name}/#{operation}"
            add_method_tracer operation, "ActiveMerchant/gateway/#{gateway_name}", :push_scope => false
            add_method_tracer operation, "ActiveMerchant/operation/#{operation}", :push_scope => false
          end
        end
      end
    end
  end
end
