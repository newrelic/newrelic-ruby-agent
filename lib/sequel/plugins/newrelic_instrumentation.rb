# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'sequel' unless defined?( Sequel )
require 'newrelic_rpm' unless defined?( NewRelic )
require 'new_relic/agent/instrumentation/active_record_helper'

module Sequel
  module Plugins
    module NewrelicInstrumentation

      module MethodTracer

        # Make a lambda for the method body of the traced method
        def make_tracer_method( metric, options )
          body = Proc.new do |*args, &block|
            classname = self.respond_to?( :name ) ? self.name : self.class.name
            metric = metric.gsub( /%CLASS%/, classname )
            trace_execution_scoped( metric, options ) do
              super( *args, &block )
            end
          end

          return body
        end

        # Override since the methods that need tracing don't exist yet
        # in the module, so we can't alias anything.
        def add_method_tracer( method_name, metric, options={} )
          body = make_tracer_method( metric, options )
          define_method( method_name, &body )
        end

      end # module MethodTracer


      module InstanceMethods
        include NewRelic::Agent::MethodTracer
        extend Sequel::Plugins::NewrelicInstrumentation::MethodTracer

        add_method_tracer :delete, 'ActiveRecord/%CLASS%/delete'
        add_method_tracer :destroy, 'ActiveRecord/%CLASS%/destroy'
        add_method_tracer :update, 'ActiveRecord/%CLASS%/update'
        add_method_tracer :update_all, 'ActiveRecord/%CLASS%/update_all'
        add_method_tracer :update_except, 'ActiveRecord/%CLASS%/update_except'
        add_method_tracer :update_fields, 'ActiveRecord/%CLASS%/update_fields'
        add_method_tracer :update_only, 'ActiveRecord/%CLASS%/update_only'
        add_method_tracer :save, 'ActiveRecord/%CLASS%/save'

      end # module InstanceMethods


      module ClassMethods
        include NewRelic::Agent::MethodTracer
        extend Sequel::Plugins::NewrelicInstrumentation::MethodTracer

        add_method_tracer :[], 'ActiveRecord/%CLASS%/get'
        add_method_tracer :all, 'ActiveRecord/%CLASS%/all'
        add_method_tracer :first, 'ActiveRecord/%CLASS%/first'
        add_method_tracer :create, 'ActiveRecord/%CLASS%/create'
      end

    end # module NewRelicInstrumentation
  end # module Plugins
end # module Sequel

