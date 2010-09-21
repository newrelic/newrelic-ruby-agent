# NewRelic instrumentation for DataMapper
#
# NOTE: Changed all the base references to "Database/", lacking any docs
# explaining why they needed to remain "AR", and following the conventions used
# by all the other rpm-contrib database instrumentations.
#
# FIXME:
#
#   (1) Still missing the instrumentation to catch all SELs (effect is that some
#       SQL breakdowns contain more than one SQL statement).

if defined? ::DataMapper

  # DM::Model class methods
  #
  # Need to capture the ! methods too (bypass validation/don't hydrate
  # instances)
  ::DataMapper::Model.class_eval do

    add_method_tracer :get,      'Database/#{self.name}/get'
    add_method_tracer :first,    'Database/#{self.name}/first'
    add_method_tracer :last,     'Database/#{self.name}/last'
    add_method_tracer :all,      'Database/#{self.name}/all'

    add_method_tracer :create,   'Database/#{self.name}/create'
    add_method_tracer :create!,  'Database/#{self.name}/create'
    add_method_tracer :update,   'Database/#{self.name}/update'
    add_method_tracer :update!,  'Database/#{self.name}/update'
    add_method_tracer :destroy,  'Database/#{self.name}/destroy'
    add_method_tracer :destroy!, 'Database/#{self.name}/destroy'

    # For partial dm-ar-finders and dm-aggregates support:
    for method in [ :aggregate, :find, :find_by_sql ] do
      next unless method_defined? method
      add_method_tracer(method, 'Database/#{self.name}/' + method.to_s)
    end

  end

  ::DataMapper::Collection.class_eval do
    add_method_tracer :get,      'Database/#{self.name}/get'
    add_method_tracer :first,    'Database/#{self.name}/first'
    add_method_tracer :last,     'Database/#{self.name}/last'
    #add_method_tracer :all,      'Database/#{self.name}/all'

    add_method_tracer :create,   'Database/#{self.name}/create'
    add_method_tracer :create!,  'Database/#{self.name}/create'
    add_method_tracer :update,   'Database/#{self.name}/update'
    add_method_tracer :update!,  'Database/#{self.name}/update'
    add_method_tracer :destroy,  'Database/#{self.name}/destroy'
    add_method_tracer :destroy!, 'Database/#{self.name}/destroy'

    # For dm-aggregates support:
    for method in [ :aggregate, :find ] do
      next unless method_defined? method
      add_method_tracer(method, 'Database/#{self.name}/' + method.to_s)
    end
  end

  # DM's Model instance (Resource) methods
  #
  # FIXME: The value of the old "execute"/load is fairly shallow, as it gets
  # called a lot just to access models that may have already been loaded through
  # SEL on the Collection, though that's not always the case as SEL might also
  # trigger additional SQL to get lazy-loaded attributes.  Sure does clutter up
  # the traces though.  While they don't seem to be tied to the generation of
  # SQL queries, I suspect this is related to balls
  #
  # NOTE: The AR instrumentation appears to always put "ActiveRecord/all" as an
  # encapsulating scope.  Since these are basically the CRUD methods, I changed
  # all the :push_scope => false versions to 'Database/all'.

  ::DataMapper::Resource.class_eval do

    #for method in [:query] do
    #  add_method_tracer method, 'Database/#{self.class.name[/[^:]*$/]}/load'
    #  add_method_tracer method, 'Database/all', :push_scope => false
    #end

    for method in [:update, :save] do
      add_method_tracer method, 'Database/#{self.class.name[/[^:]*$/]}/save'
      add_method_tracer method, 'Database/all', :push_scope => false
    end

    add_method_tracer :destroy, 'Database/#{self.class.name[/[^:]*$/]}/destroy'
    add_method_tracer :destroy, 'Database/all', :push_scope => false

  end

  ::DataMapper::Transaction.module_eval do
    add_method_tracer :commit, 'Database/#{self.class.name[/[^:]*$/]}/transaction'
  end if defined? ::DataMapper::Transaction

  # TODO: Figure out what these were (from AR instrumentation):
  #  NewRelic::Control.instance['disable_activerecord_instrumentation']
  #  NewRelic::Control.instance['skip_ar_instrumentation']
  module NewRelic
    module Agent
      module Instrumentation
        module DataMapperInstrumentation

          def self.included(klass)
            klass.class_eval do
              alias_method :log_without_newrelic_instrumentation, :log
              alias_method :log, :log_with_newrelic_instrumentation
            end
          end

          # Unlike in AR, log is called in DM after the query actually ran, with
          # duration and so forth.  Since already have metrics, there's nothing
          # more to measure, so just log.
          #
          # NOTE: NewRelic::Agent.instance.transaction_sampler.scope_depth
          # starts at 0 in sinatra, so the old test for < 2 is worthless.
          #
          # NOTE: Tried to copy the AR instrumentation, but I can't entirely
          # intuit how the [] of metrics for trace_execution_scoped interplays
          # with the rest of a given trace.
          #
          # It looks as if the AR instrumentation builds the scope as:
          #
          #  [
          #    metric = ActiveRecord/#{model}/#{operation} ||
          #             NewRelic::Agent::Instrumentation::MetricFrame.database_metric_name ||
          #             Database/SQL/{select,update,insert,delete,show,other} || nil,
          #    ActiveRecord/all,
          #    ActiveRecord/#{operation},
          #  ]
          #
          # and avoids notice_sql if it couldn't discern the metric (nil).
          #
          # TODO: Do we need to do anything with trace_execution_scoped() here?
          # Problem is, at this point in DO we can't determine what the
          # Adapter's CRUD operation was, though we could infer it from the SQL.
          #
          def log_with_newrelic_instrumentation(msg)
            # TODO: What is the expected format of the configuration (2nd arg)?
            if NewRelic::Agent.is_execution_traced?
              NewRelic::Agent.instance.transaction_sampler.notice_sql(msg.query, nil, msg.duration / 1000000.0)
            end
          ensure
            log_without_newrelic_instrumentation(msg)
          end
        end # DataMapperInstrumentation

      end # Instrumentation
    end # Agent
  end # NewRelic

  ::DataObjects::Connection.class_eval do
    include ::NewRelic::Agent::Instrumentation::DataMapperInstrumentation
  end

end # if defined? DataMapper
