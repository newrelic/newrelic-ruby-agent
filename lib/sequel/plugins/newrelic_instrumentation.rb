# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'sequel' unless defined?( Sequel )
require 'newrelic_rpm' unless defined?( NewRelic )
require 'new_relic/agent/instrumentation/sequel_helper'
require 'new_relic/agent/datastores/metric_helper'

module Sequel
  module Plugins

    # Sequel::Model instrumentation for the New Relic agent.
    module NewrelicInstrumentation

      # Meta-programming for creating method tracers for the Sequel::Model plugin.
      module MethodWrapping

        # Make a lambda for the method body of the traced method
        def make_wrapper_method(method_name)
          body = Proc.new do |*args, &block|
            klass = self.is_a?(Class) ? self : self.class

            product = NewRelic::Agent::Instrumentation::SequelHelper.product_name_from_adapter(db.adapter_scheme)
            metrics = ::NewRelic::Agent::Datastores::MetricHelper.metrics_for(product, method_name, klass.name)

            trace_execution_scoped(metrics) do
              NewRelic::Agent.disable_all_tracing { super(*args, &block) }
            end
          end

          return body
        end

        # Install a method named +method_name+ that will trace execution
        # with a metric name derived from +operation_name+ (or +method_name+ if +operation_name+
        # isn't specified).
        def wrap_sequel_method(method_name, operation_name=nil)
          operation_name ||= method_name.to_s

          body = make_wrapper_method(operation_name)
          define_method(method_name, &body)
        end

      end # module MethodTracer


      # Methods to be added to Sequel::Model instances.
      module InstanceMethods
        include NewRelic::Agent::MethodTracer
        extend Sequel::Plugins::NewrelicInstrumentation::MethodWrapping

        wrap_sequel_method :delete
        wrap_sequel_method :destroy
        wrap_sequel_method :update
        wrap_sequel_method :update_all
        wrap_sequel_method :update_except
        wrap_sequel_method :update_fields
        wrap_sequel_method :update_only
        wrap_sequel_method :save

      end # module InstanceMethods


      # Methods to be added to Sequel::Model classes.
      module ClassMethods
        include NewRelic::Agent::MethodTracer
        extend Sequel::Plugins::NewrelicInstrumentation::MethodWrapping

        wrap_sequel_method :[], "get"
        wrap_sequel_method :all
        wrap_sequel_method :first
        wrap_sequel_method :create
      end # module ClassMethods

    end # module NewRelicInstrumentation
  end # module Plugins
end # module Sequel
