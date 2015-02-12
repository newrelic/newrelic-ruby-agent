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
  end

  executes do
    DataMapper::Model.class_eval do
      add_method_tracer :get,      'ActiveRecord/#{self.name}/get'
      add_method_tracer :first,    'ActiveRecord/#{self.name}/first'
      add_method_tracer :last,     'ActiveRecord/#{self.name}/last'
      add_method_tracer :all,      'ActiveRecord/#{self.name}/all'

      add_method_tracer :create,   'ActiveRecord/#{self.name}/create'
      add_method_tracer :create!,  'ActiveRecord/#{self.name}/create'
      add_method_tracer :update,   'ActiveRecord/#{self.name}/update'
      add_method_tracer :update!,  'ActiveRecord/#{self.name}/update'
      add_method_tracer :destroy,  'ActiveRecord/#{self.name}/destroy'
      add_method_tracer :destroy!, 'ActiveRecord/#{self.name}/destroy'

      # For dm-aggregates and partial dm-ar-finders support:
      for method in [ :aggregate, :find, :find_by_sql ] do
        next unless method_defined? method
        add_method_tracer(method, 'ActiveRecord/#{self.name}/' + method.to_s)
      end

    end
  end

  executes do
    DataMapper::Resource.class_eval do
      add_method_tracer :update,   'ActiveRecord/#{self.class.name[/[^:]*$/]}/update'
      add_method_tracer :update!,  'ActiveRecord/#{self.class.name[/[^:]*$/]}/update'
      add_method_tracer :save,     'ActiveRecord/#{self.class.name[/[^:]*$/]}/save'
      add_method_tracer :save!,    'ActiveRecord/#{self.class.name[/[^:]*$/]}/save'
      add_method_tracer :destroy,  'ActiveRecord/#{self.class.name[/[^:]*$/]}/destroy'
      add_method_tracer :destroy!, 'ActiveRecord/#{self.class.name[/[^:]*$/]}/destroy'

    end
  end

  executes do
    DataMapper::Collection.class_eval do
      # DM's Collection instance methods
      add_method_tracer :get,       'ActiveRecord/#{self.name}/get'
      add_method_tracer :first,     'ActiveRecord/#{self.name}/first'
      add_method_tracer :last,      'ActiveRecord/#{self.name}/last'
      add_method_tracer :all,       'ActiveRecord/#{self.name}/all'

      add_method_tracer :lazy_load, 'ActiveRecord/#{self.name}/lazy_load'

      add_method_tracer :create,    'ActiveRecord/#{self.name}/create'
      add_method_tracer :create!,   'ActiveRecord/#{self.name}/create'
      add_method_tracer :update,    'ActiveRecord/#{self.name}/update'
      add_method_tracer :update!,   'ActiveRecord/#{self.name}/update'
      add_method_tracer :destroy,   'ActiveRecord/#{self.name}/destroy'
      add_method_tracer :destroy!,  'ActiveRecord/#{self.name}/destroy'

      # For dm-aggregates support:
      for method in [ :aggregate ] do
        next unless method_defined? method
        add_method_tracer(method, 'ActiveRecord/#{self.name}/' + method.to_s)
      end

    end
  end
end

DependencyDetection.defer do

  depends_on do
    defined?(::DataMapper) &&
      defined?(::DataMapper::Adapters) &&
      defined?(::DataMapper::Adapters::DataObjectsAdapter)
  end

  executes do
    # Catch the two entry points into DM::Repository::Adapter that bypass CRUD
    # (for when SQL is run directly).
    ::DataMapper::Adapters::DataObjectsAdapter.class_eval do
      add_method_tracer :select,  'ActiveRecord/#{self.class.name[/[^:]*$/]}/select'
      add_method_tracer :execute, 'ActiveRecord/#{self.class.name[/[^:]*$/]}/execute'
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
    DataMapper::Validations::ClassMethods.class_eval do
      next unless method_defined? :create
      add_method_tracer :create,   'ActiveRecord/#{self.name}/create'
    end
  end
end

DependencyDetection.defer do

  depends_on do
    defined?(DataMapper) && defined?(DataMapper::Transaction)
  end

  # NOTE: DM::Transaction basically calls commit() twice, so as-is it will show
  # up in traces twice -- second time subordinate to the first's scope.  Works
  # well enough.
  executes do
    DataMapper::Transaction.module_eval do
      add_method_tracer :commit, 'ActiveRecord/#{self.class.name[/[^:]*$/]}/commit'
    end
  end
end


module NewRelic
  module Agent
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
          return unless operation = case NewRelic::Helper.correctly_encoded(msg.query)
                                    when /^\s*select/i          then 'find'
                                    when /^\s*(update|insert)/i then 'save'
                                    when /^\s*delete/i          then 'destroy'
                                    else nil
                                    end

          # FYI: self.to_s will yield connection URI string.
          duration = msg.duration / 1000000.0

          # Attach SQL to current segment/scope.
          NewRelic::Agent.instance.transaction_sampler.notice_sql(msg.query, nil, duration, state)

          # Record query duration associated with each of the desired metrics.
          metric = "ActiveRecord/#{operation}"
          rollup_metrics = ActiveRecordHelper.rollup_metrics_for(metric)
          metrics = [metric] + rollup_metrics
          NewRelic::Agent.instance.stats_engine.tl_record_unscoped_metrics(metrics, duration)
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
