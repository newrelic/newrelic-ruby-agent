# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'sequel' unless defined?( Sequel )
require 'newrelic_rpm' unless defined?( NewRelic )

module Sequel
  module Plugins

    # Sequel::Model instrumentation for the New Relic agent.
    module NewrelicInstrumentation

      # Meta-programming for creating method tracers for the Sequel::Model plugin.
      module MethodTracer

        # Make a lambda for the method body of the traced method
        def make_tracer_method( opname, options )
          body = Proc.new do |*args, &block|
            classname = self.is_a?( Class ) ? self.name : self.class.name
            metric = "ActiveRecord/%s/%s" % [ classname, opname ]
            trace_execution_scoped( metric, options ) do
              super( *args, &block )
            end
          end

          return body
        end

        # Install a method named +method_name+ that will trace execution
        # with a metric name derived from +metric+ (or +method_name+ if +metric+
        # isn't specified). The +options+ hash is passed as-is though to
        # NewRelic::Agent::MethodTracer#trace_execution_scoped; see the
        # docs for that method for valid settings.
        def add_method_tracer( method_name, metric=nil, options={} )
          # Shift options hash if metric is omitted
          if metric.is_a?( Hash )
            options = metric
            metric = nil
          end

          metric ||= method_name.to_s

          body = make_tracer_method( metric, options )
          define_method( method_name, &body )
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

        add_method_tracer :[], :get
        add_method_tracer :all
        add_method_tracer :first
        add_method_tracer :create
      end # module ClassMethods

    end # module NewRelicInstrumentation
  end # module Plugins
end # module Sequel
