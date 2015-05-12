# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'sequel' unless defined?( Sequel )
require 'newrelic_rpm' unless defined?( NewRelic )
require 'new_relic/agent/instrumentation/sequel_helper'
require 'new_relic/agent/datastores/metric_helper'

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

    # Instrument all queries that go through #execute_query.
    def log_yield(sql, args=nil) #THREAD_LOCAL_ACCESS
      rval = nil
      product = NewRelic::Agent::Instrumentation::SequelHelper.product_name_from_adapter(self.class.adapter_scheme)
      metrics = NewRelic::Agent::Datastores::MetricHelper.metrics_from_sql(product, sql)
      scoped_metric = metrics.first

      NewRelic::Agent::MethodTracer.trace_execution_scoped(metrics) do
        t0 = Time.now
        begin
          rval = super
        ensure
          notice_sql(sql, scoped_metric, args, t0, Time.now)
        end
      end

      return rval
    end

    THREAD_SAFE_CONNECTION_POOL_CLASSES = [
      (defined?(::Sequel::ThreadedConnectionPool) && ::Sequel::ThreadedConnectionPool)
    ].freeze

    def notice_sql(sql, metric_name, args, start, finish)
      state    = NewRelic::Agent::TransactionState.tl_get
      duration = finish - start

      explainer = Proc.new do |*|
        if THREAD_SAFE_CONNECTION_POOL_CLASSES.include?(self.pool.class)
          self[ sql ].explain
        else
          NewRelic::Agent.logger.log_once(:info, :sequel_explain_skipped, "Not running SQL explains because Sequel is not in recognized multi-threaded mode")
          nil
        end
      end
      NewRelic::Agent.instance.transaction_sampler.notice_sql(sql, self.opts, duration, state, explainer)
      NewRelic::Agent.instance.sql_sampler.notice_sql(sql, metric_name, self.opts, duration, state, explainer)
    end

  end # module NewRelicInstrumentation

  NewRelic::Agent.logger.debug "Registering the :newrelic_instrumentation extension."
  Database.register_extension(:newrelic_instrumentation, NewRelicInstrumentation)

end # module Sequel
