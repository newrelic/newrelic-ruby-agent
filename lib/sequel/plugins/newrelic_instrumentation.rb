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
      module MethodTracer

        # Make a lambda for the method body of the traced method
        def make_tracer_method(method_name)
          body = Proc.new do |*args, &block|
            klass = self.is_a?(Class) ? self : self.class

            operation = NewRelic::Agent::Instrumentation::SequelHelper.operation_from_method_name(method_name)
            metric = "Datastore/statement/SQLite/%s/%s" % [ klass.table_name, operation ]
            metrics = ::NewRelic::Agent::Datastores::MetricHelper.metrics_for('SQLite', operation, klass.table_name)

            trace_execution_scoped(metrics) do
              NewRelic::Agent.disable_all_tracing { super(*args, &block) }
            end
          end

          return body
        end

        # Install a method named +method_name+ that will trace execution
        # with a metric name derived from +operation_name+ (or +method_name+ if +operation_name+
        # isn't specified).
        def add_method_tracer(method_name, operation_name=nil)
          operation_name ||= method_name.to_s

          body = make_tracer_method(operation_name)
          define_method(method_name, &body)
        end

      end # module MethodTracer


      # Methods to be added to Sequel::Model instances.
      module InstanceMethods
        include NewRelic::Agent::MethodTracer
        extend Sequel::Plugins::NewrelicInstrumentation::MethodTracer

        add_method_tracer :delete
        add_method_tracer :destroy
        add_method_tracer :update
        add_method_tracer :update_all
        add_method_tracer :update_except
        add_method_tracer :update_fields
        add_method_tracer :update_only
        add_method_tracer :save

      end # module InstanceMethods


      # Methods to be added to Sequel::Model classes.
      module ClassMethods
        include NewRelic::Agent::MethodTracer
        extend Sequel::Plugins::NewrelicInstrumentation::MethodTracer

        add_method_tracer :[], "get"
        add_method_tracer :all
        add_method_tracer :first
        add_method_tracer :create
      end # module ClassMethods

    end # module NewRelicInstrumentation
  end # module Plugins
end # module Sequel
