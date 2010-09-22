## NewRelic instrumentation for DataMapper
#
# Instrumenting DM has different key challenges versus AR:
#
#   1. The hooking of SQL logging in DM is decoupled from any knowledge of the
#      Model#method that invoked it.  But on the positive side, the duration is
#      already calculated for you (and it happens inside the C-based DO code, so
#      it's faster than a Ruby equivalent).
#
#   2. There are a lot more entry points that need to be hooked in order to
#      understand call flow: DM::Model (model class) vs. DM::Resource (model
#      instance) vs. DM::Collection (collection of model instances).  And
#      others.
#
#   3. Strategic Eager Loading (SEL) combined with separately-grouped
#      lazy-loaded attributes presents a unique problem for tying resulting
#      SEL-invoked SQL calls to their proper scope.
#
# NOTE: On using "Database" versus "ActiveRecord" as base metric name
#
#   Using "Database" as the metric name base seems to properly identify methods
#   as being DB-related in call graphs, but certain RPM views that show
#   aggregations of DB CPM, etc still seem to rely solely on "ActiveRecord"
#   being the base name, thus AFAICT "Database" calls to this are lost.  (Though
#   I haven't yet tested "Database/SQL/{find/save/destroy/all}" yet, as it seems
#   like an intuitively good name to use.)
#
#   So far I think these are the rules:
#
#     - ActiveRecord/{find/save/destroy} populates "Database Throughput" and
#       "Database Response Time" in the Database tab. [non-scoped]
#
#     - ActiveRecord/all populates the main Overview tab of DB time.  (still
#       unsure about this one). [non-scoped]
#
#     These metrics are represented as :push_scope => false or included as the
#     non-first metric in trace_execution_scoped() (docs say only first counts
#     towards scope) so they don't show up ine normal call graph/trace.
#
# TODO: Move recording of all "non-scoped metrics" into the log hook, inferring
#       what type of operation it is from the SQL itself.
#
#      This is probably a more complete approach because the find/save/destroy
#      metrics are currently recorded from hooking calls on DM::Resource.  There
#      are other entry points that result in SQL: DM::Model calls that don't
#      hydrate objects, direct calls to repository.adapter.select()/execute(),
#      and probably others.
#
# FIXME:
#
#   (1) Multiple SQL queries sometimes show up under a single trace scope.
#
#       The symptom occurs because of multiple calls to notice_sql() while under
#       the same current_segment scope.  In other words, I think it's
#       symptomatic of some missing/uninstrumented "entry points" that would
#       otherwise have shown up as separate new line items in the trace call
#       graph with the related SQL attached to it instead.
#
#   (2) Database/#{model}/#{method} populates the "Database / Top 5 operations"
#       graph key correctly, but no data for them will actually show up.
#       Switching to AR corrects this.
#
#   (3) Hooking DM::Resource#query appears to catch SEL cases (I *think*), so I
#       named the metric "load".  However I don't observe any SQL being attached
#       to the scope of those calls, so possible causes:
#
#       (a) something is wrong with either the code or my assumptions related to
#           how current_segment/scope works when notice_* functions are called
#
#       (b) I'm straight up wrong about DM::Resource#query being invoked to SEL
#           lazy-loaded attributes
#
#       But for certain DM::Resource#query is being invoked to do *something*
#       that is probably useful in this context.
#
#   (4) As I experiment with this, the DeveloperMode transaction trace/call
#       graph listings seem to differ in what is shown and how.

if defined? ::DataMapper

  # DM::Model class methods
  #
  # Need to capture the ! methods too (bypass validation/don't hydrate
  # instances)
  ::DataMapper::Model.class_eval do

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

    # For partial dm-ar-finders and dm-aggregates support:
    for method in [ :aggregate, :find, :find_by_sql ] do
      next unless method_defined? method
      add_method_tracer(method, 'ActiveRecord/#{self.name}/' + method.to_s)
    end

  end

  ::DataMapper::Collection.class_eval do
    add_method_tracer :get,      'ActiveRecord/#{self.name}/get'
    add_method_tracer :first,    'ActiveRecord/#{self.name}/first'
    add_method_tracer :last,     'ActiveRecord/#{self.name}/last'

    # NOTE: Appears to be some weirdness related to "all" as a bucket keyword,
    # so leaving out for now.
    #add_method_tracer :all,      'ActiveRecord/#{self.name}/all'

    add_method_tracer :create,   'ActiveRecord/#{self.name}/create'
    add_method_tracer :create!,  'ActiveRecord/#{self.name}/create'
    add_method_tracer :update,   'ActiveRecord/#{self.name}/update'
    add_method_tracer :update!,  'ActiveRecord/#{self.name}/update'
    add_method_tracer :destroy,  'ActiveRecord/#{self.name}/destroy'
    add_method_tracer :destroy!, 'ActiveRecord/#{self.name}/destroy'

    # For dm-aggregates support:
    for method in [ :aggregate, :find ] do
      next unless method_defined? method
      add_method_tracer(method, 'ActiveRecord/#{self.name}/' + method.to_s)
    end
  end

  # DM's Model instance (Resource) methods
  #
  # FIXME: The value of the old "execute"/load seems to be fairly shallow, as it
  # gets called a lot just to access models that may have already been loaded
  # through SEL on the Collection, though that's not always the case as SEL
  # might also trigger additional SQL to get lazy-loaded attributes.  Sure does
  # clutter up the traces though.  Noted in FIXMEs at top.

  ::DataMapper::Resource.class_eval do

    for method in [:query] do
      add_method_tracer method, 'ActiveRecord/#{self.class.name[/[^:]*$/]}/load'
      add_method_tracer method, 'ActiveRecord/find', :push_scope => false
    end

    for method in [:update, :save] do
      add_method_tracer method, 'ActiveRecord/#{self.class.name[/[^:]*$/]}/save'
      add_method_tracer method, 'ActiveRecord/save', :push_scope => false
    end

    for method in [:destroy] do
      add_method_tracer method, 'ActiveRecord/#{self.class.name[/[^:]*$/]}/destroy'
      add_method_tracer method, 'ActiveRecord/destroy', :push_scope => false
    end

  end

  # NOTE: DM::Transaction basically calls commit() twice, so as-is it will show
  # up in traces twice -- second time subordinate to the first's scope.  Works
  # well enough.
  ::DataMapper::Transaction.module_eval do
    add_method_tracer :commit, 'ActiveRecord/#{self.class.name[/[^:]*$/]}/commit'
  end if defined? ::DataMapper::Transaction

  # TODO: Figure out what these were (from AR instrumentation) and whether we
  # should support them too:
  #
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
          # duration and so forth.  Since DO already has our metrics, there's
          # nothing more to measure, so just log.
          #
          # TODO: Tried to copy the AR instrumentation, but I can't entirely
          # intuit how the [] of metrics for trace_execution_scoped interplays
          # with the rest of a given trace.  trace_execution_unscoped also seems
          # to have unexpected effects.  For now, we just assume that all the
          # right entry points have been traced (with scope) from above, and
          # thus we're already inside the correct scope when we attach the SQL
          # to it with notice_sql.
          #
          # FWIW it looks like the AR instrumentation builds the scope as:
          #
          #  [
          #    metric = ActiveRecord/#{model}/#{operation} ||
          #             NewRelic::Agent::Instrumentation::MetricFrame.database_metric_name ||
          #             Database/SQL/{select,update,insert,delete,show,other} || nil,
          #    ActiveRecord/all,
          #    ActiveRecord/#{operation},
          #  ]
          #
          # and omits notice_sql if it couldn't discern the first metric (nil
          # case).  Probably because trace_execution_scoped uses the first entry
          # as the scope.
          #
          # TODO: Do we need to do anything with trace_execution_scoped() here?
          # Problem is, at this point in DO we can't determine what the
          # Adapter's CRUD operation was, though we could infer it from the SQL.
          #
          def log_with_newrelic_instrumentation(msg)
            return unless NewRelic::Agent.is_execution_traced?
            NewRelic::Agent.instance.transaction_sampler.notice_sql(msg.query, nil, msg.duration / 1000000.0)
          ensure
            log_without_newrelic_instrumentation(msg)
          end

          # NOTE: This is me trying to employ trace_execution_*scoped to record
          # non-scoped aggregation metrics.  Both invocations still producing
          # bad shit in the call graph inside Developer Mode though.
=begin
          def log_with_newrelic_instrumentation(msg)
            return unless NewRelic::Agent.is_execution_traced?
            return unless operation = case msg.query
              when /^select/i          then 'find'
              when /^(update|insert)/i then 'save'
              when /^delete/i          then 'destroy'
              else nil
            end

            metrics = [ "ActiveRecord/#{operation}", 'ActiveRecord/all' ]
            self.class.trace_execution_unscoped(metrics) do
              # TODO: What is the expected format of the configuration (2nd arg)?
              NewRelic::Agent.instance.transaction_sampler.notice_sql(msg.query, nil, msg.duration / 1000000.0)
            end
=end
        end # DataMapperInstrumentation

      end # Instrumentation
    end # Agent
  end # NewRelic

  ::DataObjects::Connection.class_eval do
    include ::NewRelic::Agent::Instrumentation::DataMapperInstrumentation
  end

end # if defined? DataMapper
