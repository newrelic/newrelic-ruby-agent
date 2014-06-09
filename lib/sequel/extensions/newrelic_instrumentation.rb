# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'sequel' unless defined?( Sequel )
require 'newrelic_rpm' unless defined?( NewRelic )
require 'new_relic/agent/instrumentation/active_record_helper'

module Sequel

  # New Relic's Sequel instrumentation is implemented via a plugin for
  # Sequel::Models, and an extension for Sequel::Databases. Every database
  # handle that Sequel knows about when New Relic is loaded will automatically
  # be instrumented, but if you're using a version of Sequel before 3.47.0,
  # you'll need to add the extension yourself if you create any after the
  # instrumentation is loaded:
  #
  #     db = Sequel.connect( ... )
  #     db.extension :newrelic_instrumentation
  #
  # Versions 3.47.0 and later use `Database.extension` to automatically
  # install the extension for new connections.
  #
  # == Disabling
  #
  # If you don't want your models or database connections to be instrumented,
  # you can disable them by setting `disable_database_instrumentation` in
  # your `newrelic.yml` to `true`. It will also honor the
  # `disable_activerecord_instrumentation` setting.
  #
  module NewRelicInstrumentation
    include NewRelic::Agent::MethodTracer,
            NewRelic::Agent::Instrumentation::ActiveRecordHelper


    # Instrument all queries that go through #execute_query.
    def log_yield(sql, args=nil) #THREAD_LOCAL_ACCESS
      state = NewRelic::Agent::TransactionState.tl_get
      return super unless state.is_execution_traced?

      t0 = Time.now
      rval = super
      t1 = Time.now

      begin
        duration = t1 - t0
        record_metrics(sql, args, duration)
        notice_sql(state, sql, args, t0, t1)
      rescue => err
        NewRelic::Agent.logger.debug "while recording metrics for Sequel", err
      end

      return rval
    end

    # Record metrics for the specified +sql+ and +args+ using the specified
    # +duration+.
    def record_metrics(sql, args, duration) #THREAD_LOCAL_ACCESS
      primary_metric = primary_metric_for(sql, args)
      engine         = NewRelic::Agent.instance.stats_engine

      metrics = rollup_metrics_for(primary_metric)
      metrics << remote_service_metric(*self.opts.values_at(:adapter, :host)) if self.opts.key?(:adapter)

      engine.tl_record_scoped_and_unscoped_metrics(primary_metric, metrics, duration)
    end

    THREAD_SAFE_CONNECTION_POOL_CLASSES = [
      (defined?(::Sequel::ThreadedConnectionPool) && ::Sequel::ThreadedConnectionPool),
    ].compact.freeze

    # Record the given +sql+ within a new frame, using the given +start+ and
    # +finish+ times.
    def notice_sql(state, sql, args, start, finish)
      metric   = primary_metric_for(sql, args)
      agent    = NewRelic::Agent.instance
      duration = finish - start
      stack    = state.traced_method_stack

      begin
        frame = stack.push_frame(state, :sequel, start)
        explainer = Proc.new do |*|
          if THREAD_SAFE_CONNECTION_POOL_CLASSES.include?(self.pool.class)
            self[ sql ].explain
          else
            NewRelic::Agent.logger.log_once(:info, :sequel_explain_skipped, "Not running SQL explains because Sequel is not in recognized multi-threaded mode")
            nil
          end
        end
        agent.transaction_sampler.notice_sql(sql, self.opts, duration, state, &explainer)
        agent.sql_sampler.notice_sql(sql, metric, self.opts, duration, state, &explainer)
      ensure
        stack.pop_frame(state, frame, metric, finish)
      end
    end


    # Derive a primary database metric for the specified +sql+.
    def primary_metric_for(sql, _)
      return metric_for_sql(NewRelic::Helper.correctly_encoded(sql))
    end

  end # module NewRelicInstrumentation

  NewRelic::Agent.logger.debug "Registering the :newrelic_instrumentation extension."
  Database.register_extension(:newrelic_instrumentation, NewRelicInstrumentation)

end # module Sequel
