# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  named :data_mapper

  depends_on do
    defined?(::DataMapper) &&
      defined?(::DataMapper::Model) &&
      defined?(::DataMapper::Resource) &&
      defined?(::DataMapper::Collection)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing DataMapper instrumentation'
    require 'new_relic/agent/datastores/metric_helper'
  end

  executes do
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Model, :get
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Model, :first
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Model, :last
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Model, :all

    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Model, :create
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Model, :create!
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Model, :update
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Model, :update!
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Model, :destroy
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Model, :destroy!

    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Model, :aggregate
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Model, :find
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Model, :find_by_sql
  end

  executes do
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Resource, :update
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Resource, :update!
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Resource, :save
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Resource, :save!
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Resource, :destroy
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Resource, :destroy!
  end

  executes do
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Collection, :get
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Collection, :first
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Collection, :last
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Collection, :all

    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Collection, :lazy_load

    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Collection, :create
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Collection, :create!
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Collection, :update
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Collection, :update!
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Collection, :destroy
    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Collection, :destroy!

    NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Collection, :aggregate
  end

  executes do
    # Catch the two entry points into DM::Repository::Adapter that bypass CRUD
    # (for when SQL is run directly).
    if defined?(::DataMapper::Adapters::DataObjectsAdapter)
      NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Adapters::DataObjectsAdapter, :select, true
      NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Adapters::DataObjectsAdapter, :execute, true
    end
  end
end

DependencyDetection.defer do

  depends_on do
    defined?(::DataMapper) &&
      defined?(::DataMapper::Validations) &&
      defined?(::DataMapper::Validations::ClassMethods)
  end

  # DM::Validations overrides Model#create, but currently in a way that makes it
  # impossible to instrument from one place.  I've got a patch pending inclusion
  # to make it instrumentable by putting the create method inside ClassMethods.
  # This will pick it up if/when that patch is accepted.
  executes do
    ::DataMapper::Validations::ClassMethods.class_eval do
      NewRelic::Agent::DataMapperTracing.add_tracer ::DataMapper::Validations::ClassMethods, :create
    end
  end
end

DependencyDetection.defer do
  depends_on do
    defined?(::DataMapper) &&
      defined?(::DataMapper::Transaction)
  end

  # NOTE: DM::Transaction basically calls commit() twice, so as-is it will show
  # up in traces twice -- second time subordinate to the first's scope.  Works
  # well enough.
  executes do
    ::DataMapper::Transaction.module_eval do
      add_method_tracer :commit, 'ActiveRecord/#{self.class.name[/[^:]*$/]}/commit'
    end
  end
end

module NewRelic
  module Agent
    module DataMapperTracing
      def self.add_tracer(clazz, method_name, operation_only = false)
        clazz.class_eval do
          if method_defined?(method_name)
            define_method("#{method_name}_with_newrelic",
                          NewRelic::Agent::DataMapperTracing.method_body(method_name, operation_only))

            alias_method "#{method_name}_without_newrelic", method_name
            alias_method method_name, "#{method_name}_with_newrelic"
          end
        end
      end

      DATA_MAPPER = "DataMapper".freeze

      def self.method_body(method_name, operation_only)
        metric_operation = method_name.to_s.gsub(/[!?]/, "")

        Proc.new do |*args, &blk|
        begin
          name = self.is_a?(Class) ? self.name : self.class.name
          name = nil if operation_only

          t0 = Time.now
          metrics = NewRelic::Agent::Datastores::MetricHelper.metrics_for(
            DATA_MAPPER,
            metric_operation,
            name)

          scoped_metric = metrics.pop

          self.send("#{method_name}_without_newrelic", *args, &blk)
        ensure
          if $!
            puts $!
            puts ($!.backtrace || []).join("\n\t")
          end

          if t0
            NewRelic::Agent.instance.stats_engine.tl_record_scoped_and_unscoped_metrics(scoped_metric, metrics, Time.now - t0)
          end
        end
        end
      end
    end

    module Instrumentation
      module DataMapperInstrumentation
        # Unlike in AR, log is called in DM after the query actually ran,
        # complete with metrics.  Since DO has already calculated the
        # duration, there's nothing more to measure, so just record and log.
        #
        # We rely on the assumption that all possible entry points have been
        # hooked with tracers, ensuring that notice_sql attaches this SQL to
        # the proper call scope.
        def log(msg) #THREAD_LOCAL_ACCESS
          state = NewRelic::Agent::TransactionState.tl_get
          return unless state.is_execution_traced?

          duration = msg.duration / 1000000.0
          NewRelic::Agent.instance.transaction_sampler.notice_sql(msg.query, nil, duration, state)
        ensure
          super
        end

      end
    end
  end
end

DependencyDetection.defer do
  depends_on do
    defined?(::DataObjects) &&
      defined?(::DataObjects::Connection)
  end

  executes do
    ::DataObjects::Connection.class_eval do
      include ::NewRelic::Agent::Instrumentation::DataMapperInstrumentation
    end
  end
end
