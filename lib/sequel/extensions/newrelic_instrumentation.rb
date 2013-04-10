# -*- ruby -*-
#encoding: utf-8

require 'sequel' unless defined?( Sequel )
require 'newrelic_rpm' unless defined?( NewRelic )
require 'new_relic/agent/instrumentation/active_record_helper'

module Sequel
  module NewRelicInstrumentation
    include NewRelic::Agent::MethodTracer,
            NewRelic::Agent::Instrumentation::ActiveRecordHelper

    # Extension callback
    def self::extended( mod )
      NewRelic::Agent.logger.debug "Extending %p with %p" % [ mod, self ]
      super
    end


    # Inclusion callback
    def self::included( mod )
      NewRelic::Agent.logger.debug "Including %p in %p" % [ self, mod ]
      super
    end


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

    def record_metrics( sql, args, duration)
      NewRelic::Agent.logger.debug "Recording metrics for %p." % [ sql ]
      primary_metric = primary_metric_for( sql, args )
      engine         = NewRelic::Agent.instance.stats_engine

      engine.record_metrics( primary_metric, duration, :scoped => true )

      metrics = rollup_metrics_for( primary_metric )
      metrics << remote_service_metric( *self.opts.values_at(:adapter, :host) )

      metrics.each do |metric_name|
        engine.record_metrics( metric_name, duration, :scoped => false )
      end
    end


    # Record the SQL for the current transaction
    def notice_sql( sql, args, start, finish )
      metric   = primary_metric_for( sql, args )
      agent    = NewRelic::Agent.instance
      duration = finish - start

      scope = agent.stats_engine.push_scope( metric, start )
      agent.transaction_sampler.notice_sql( sql, self.opts, duration )
      agent.sql_sampler.notice_sql( sql, metric, self.opts, duration )
      agent.stats_engine.pop_scope( scope, duration, finish )
    end


    # Derive a primary database metric for the specified +sql+.
    def primary_metric_for( sql, _ )
      return metric_for_sql(NewRelic::Helper.correctly_encoded(sql))
    end

  end # module NewRelicInstrumentation

  NewRelic::Agent.logger.debug "Registering the :newrelic_instrumentation extension."
  Database.register_extension( :newrelic_instrumentation, NewRelicInstrumentation )

end # module Sequel

