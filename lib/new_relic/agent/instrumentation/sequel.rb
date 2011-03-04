## NewRelic instrumentation for Sequel
#
# This is based heavily on the DataMapper instrumentation.
# See data_mapper.rb for major differences compared to the ActiveRecord instrumentation.
#

DependencyDetection.defer do
  depends_on do
    defined?(::Sequel)
  end

  executes do
    # Sequel::Model class methods
    ::Sequel::Model::ClassMethods.class_eval do

      add_method_tracer :[],              'ActiveRecord/#{self.name}/find'

      add_method_tracer :all,             'ActiveRecord/#{self.name}/find'
      add_method_tracer :each,            'ActiveRecord/#{self.name}/find'
      add_method_tracer :create,          'ActiveRecord/#{self.name}/create'
      add_method_tracer :insert,          'ActiveRecord/#{self.name}/create'
      add_method_tracer :insert_multiple, 'ActiveRecord/#{self.name}/create'
      add_method_tracer :import,          'ActiveRecord/#{self.name}/create'
      add_method_tracer :update,          'ActiveRecord/#{self.name}/update'
      add_method_tracer :delete,          'ActiveRecord/#{self.name}/delete'

    end

    # Sequel's Model instance methods
    ::Sequel::Model::InstanceMethods.class_eval do

      add_method_tracer :_insert, 'ActiveRecord/#{self.class.name[/[^:]*$/]}/create'
      add_method_tracer :_update, 'ActiveRecord/#{self.class.name[/[^:]*$/]}/update'
      add_method_tracer :_delete, 'ActiveRecord/#{self.class.name[/[^:]*$/]}/destroy'

    end

    # Sequel's Dataset instance methods
    ::Sequel::Dataset.class_eval do

      add_method_tracer :execute,        'ActiveRecord/#{model ? model.name : "Dataset#{first_source}"}/find'
      add_method_tracer :execute_insert, 'ActiveRecord/#{model ? model.name : "Dataset#{first_source}"}/create'
      add_method_tracer :execute_dui,    'ActiveRecord/#{model ? model.name : "Dataset#{first_source}"}/update'
      add_method_tracer :execute_ddl,    'ActiveRecord/#{model ? model.name : "Dataset#{first_source}"}/all'

    end

    # Sequel's Database methods
    ::Sequel::Database.class_eval do

      add_method_tracer :execute,        'ActiveRecord/Database/find'
      add_method_tracer :execute_insert, 'ActiveRecord/Database/create'
      add_method_tracer :execute_dui,    'ActiveRecord/Database/update'
      add_method_tracer :execute_ddl,    'ActiveRecord/Database/all'

    end
  end
end


module NewRelic
  module Agent
    module Instrumentation
      module SequelInstrumentation
        def self.included(klass)
          klass.class_eval do
            alias_method :log_duration_without_newrelic_instrumentation, :log_duration
            alias_method :log_duration, :log_duration_with_newrelic_instrumentation
          end
        end

        def log_duration_with_newrelic_instrumentation(duration, sql)
          return unless NewRelic::Agent.is_execution_traced?
          return unless operation = case sql
                                    when /^\s*select/i          then 'find'
                                    when /^\s*(update|insert)/i then 'save'
                                    when /^\s*delete/i          then 'destroy'
                                    else nil
                                    end

          # Attach SQL to current segment/scope.
          NewRelic::Agent.instance.transaction_sampler.notice_sql(sql, nil, duration)

          # Record query duration associated with each of the desired metrics.
          metrics = [ "ActiveRecord/#{operation}", 'ActiveRecord/all' ]
          metrics.each do |metric|
            NewRelic::Agent.instance.stats_engine.get_stats_no_scope(metric).trace_call(duration)
          end
        ensure
          log_duration_without_newrelic_instrumentation(duration, sql)
        end

      end # SequelInstrumentation
    end # Instrumentation
  end # Agent
end # NewRelic

DependencyDetection.defer do
  depends_on do
    defined?(::Sequel) && defined?(::Sequel::Database)
  end
  
  executes do
    ::Sequel::Database.class_eval do
      include ::NewRelic::Agent::Instrumentation::SequelInstrumentation
    end
  end
end

