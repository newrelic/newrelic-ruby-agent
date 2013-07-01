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
    def log_yield( sql, args=nil )
      return super unless NewRelic::Agent.is_execution_traced?

      t0 = Time.now
      rval = super
      t1 = Time.now

      begin
        duration = t1 - t0
        record_metrics( sql, args, duration )
        notice_sql( sql, args, t0, t1 )
      rescue => err
        NewRelic::Agent.logger.debug "while recording metrics for Sequel", err
      end

      return rval
    end

    # Record metrics for the specified +sql+ and +args+ using the specified
    # +duration+.
    def record_metrics( sql, args, duration)
      primary_metric = primary_metric_for( sql, args )
      engine         = NewRelic::Agent.instance.stats_engine

      engine.record_metrics( primary_metric, duration, :scoped => true )

      metrics = rollup_metrics_for( primary_metric )
      metrics << remote_service_metric( *self.opts.values_at(:adapter, :host) ) if self.opts.key?(:adapter)

      engine.record_metrics( metrics, duration, :scoped => false )
    end


    # Record the given +sql+ within a new scope, using the given +start+ and
    # +finish+ times.
    def notice_sql( sql, args, start, finish )
      metric   = primary_metric_for( sql, args )
      agent    = NewRelic::Agent.instance
      duration = finish - start

      begin
        scope = agent.stats_engine.push_scope( :sequel, start )
        agent.transaction_sampler.notice_sql( sql, self.opts, duration ) do |*|
          self[ sql ].explain
        end
        agent.sql_sampler.notice_sql( sql, metric, self.opts, duration ) do |*|
          self[ sql ].explain
        end
      ensure
        agent.stats_engine.pop_scope( scope, metric, finish )
      end
    end


    # Derive a primary database metric for the specified +sql+.
    def primary_metric_for( sql, _ )
      return metric_for_sql(NewRelic::Helper.correctly_encoded(sql))
    end

  end # module NewRelicInstrumentation

  NewRelic::Agent.logger.debug "Registering the :newrelic_instrumentation extension."
  Database.register_extension( :newrelic_instrumentation, NewRelicInstrumentation )

end # module Sequel
