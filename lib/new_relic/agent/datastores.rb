# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/datastores/metric_helper'

module NewRelic
  module Agent
    #
    # This module contains helper methods to facilitate instrumentation of
    # datastores not directly supported by the Ruby agent. It is intended to be
    # primarily used by authors of 3rd-party datastore instrumentation.
    #
    # @api public
    module Datastores

      # @!group Tracing query methods

      # Add Datastore tracing to a method. This properly generates the metrics
      # for New Relic's Datastore features. It does not capture the actual
      # query content into Transaction Traces. Use wrap if you want to provide
      # that functionality.
      #
      # @param [Class] clazz the class to instrument
      #
      # @param [String, Symbol] method_name the name of instance method to
      #   instrument
      #
      # @param [String] product name of your datastore for use in metric naming, e.g. "Redis"
      #
      # @param [optional,String] operation the name of operation if different
      #   than the instrumented method name
      #
      # @api public
      #
      def self.trace(clazz, method_name, product, operation = method_name)
        if NewRelic::Helper.instance_methods_include?(clazz, method_name)
          visibility = NewRelic::Helper.instance_method_visibility(clazz, method_name)
          
          tracer_module = Module.new do
            define_method(method_name) do |*args, &blk|
              metrics = MetricHelper.metrics_for(product, operation)
              NewRelic::Agent::MethodTracer.trace_execution_scoped(metrics) do
                super(*args, &blk)
              end
            end

            send visibility, method_name
          end

          clazz.class_eval do
            prepend tracer_module
          end
        end
      end

      # Wrap a call to a datastore and record New Relic Datastore metrics. This
      # method can be used when a collection (i.e. table or model name) is
      # known at runtime to be included in the metric naming. It is intended
      # for situations that the simpler NewRelic::Agent::Datastores.trace can't
      # properly handle.
      #
      # To use this, wrap the datastore operation in the block passed to wrap.
      #
      #   NewRelic::Agent::Datastores.wrap("FauxDB", "find", "items") do
      #     FauxDB.find(query)
      #   end
      #
      # @param [String] product the datastore name for use in metric naming,
      #   e.g. "FauxDB"
      #
      # @param [String,Symbol] operation the name of operation (e.g. "select"),
      #   often named after the method that's being instrumented.
      #
      # @param [optional, String] collection the collection name for use in
      #   statement-level metrics (i.e. table or model name)
      #
      # @param [Proc,#call] callback proc or other callable to invoke after
      #   running the datastore block. Receives three arguments: result of the
      #   yield, the most specific (scoped) metric name, and elapsed time of the
      #   call. An example use is attaching SQL to Transaction Traces at the end
      #   of a wrapped datastore call.
      #
      #     callback = Proc.new do |result, metrics, elapsed|
      #       NewRelic::Agent::Datastores.notice_sql(query, metrics, elapsed)
      #     end
      #
      #     NewRelic::Agent::Datastores.wrap("FauxDB", "find", "items", callback) do
      #       FauxDB.find(query)
      #     end
      #
      # @note THERE ARE SECURITY CONCERNS WHEN CAPTURING QUERY TEXT!
      #   New Relic's Transaction Tracing and Slow SQL features will
      #   attempt to apply obfuscation to the passed queries, but it is possible
      #   for a query format to be unsupported and result in exposing user
      #   information embedded within captured queries.
      #
      # @api public
      #
      def self.wrap(product, operation, collection = nil, callback = nil)
        return yield unless operation

        metrics = MetricHelper.metrics_for(product, operation, collection)
        scoped_metric = metrics.first
        NewRelic::Agent::MethodTracer.trace_execution_scoped(metrics) do
          t0 = Time.now if callback
          begin
            result = yield
          ensure
            if callback
              elapsed_time = (Time.now - t0).to_f
              callback.call(result, scoped_metric, elapsed_time)
            end
          end
        end
      end

      # @!group Capturing query / statement text

      # Wrapper for simplifying attaching SQL queries during a transaction.
      #
      # If you are recording non-SQL data, please use {notice_statement}
      # instead.
      #
      #   NewRelic::Agent::Datastores.notice_sql(query, metrics, elapsed)
      #
      # @param [String] query the SQL text to be captured. Note that depending
      #   on user settings, this string will be run through obfuscation, but
      #   some dialects of SQL (or non-SQL queries) are not guaranteed to be
      #   properly obfuscated by these routines!
      #
      # @param [String] scoped_metric The most specific metric relating to this
      #   query. Typically the result of
      #   NewRelic::Agent::Datastores::MetricHelper#metrics_for
      #
      # @param [Float] elapsed the elapsed time during query execution
      #
      # @note THERE ARE SECURITY CONCERNS WHEN CAPTURING QUERY TEXT!
      #   New Relic's Transaction Tracing and Slow SQL features will
      #   attempt to apply obfuscation to the passed queries, but it is possible
      #   for a query format to be unsupported and result in exposing user
      #   information embedded within captured queries.
      #
      # @api public
      #
      def self.notice_sql(query, scoped_metric, elapsed)
        agent = NewRelic::Agent.instance
        agent.transaction_sampler.notice_sql(query, nil, elapsed)
        agent.sql_sampler.notice_sql(query, scoped_metric, nil, elapsed)
        nil
      end

      # Wrapper for simplifying attaching non-SQL data statements to a
      # transaction. For instance, Mongo or CQL queries, Memcached or Redis
      # keys would all be appropriate data to attach as statements.
      #
      # Data passed to this method is NOT obfuscated by New Relic, so please
      # ensure that user information is obfuscated if the agent setting
      # `transaction_tracer.record_sql` is set to `obfuscated`
      #
      #   NewRelic::Agent::Datastores.notice_statement("key", elapsed)
      #
      # @param [String] statement text of the statement to capture.
      #
      # @param [Float] elapsed the elapsed time during query execution
      #
      # @note THERE ARE SECURITY CONCERNS WHEN CAPTURING STATEMENTS!
      #   This method will properly ignore statements when the user has turned
      #   off capturing queries, but it is not able to obfuscate arbitrary data!
      #   To prevent exposing user information embedded in captured queries,
      #   please ensure all data passed to this method is safe to transmit to
      #   New Relic.
      #
      # @api public
      #
      def self.notice_statement(statement, elapsed)
        # Settings may change eventually, but for now we follow the same
        # capture rules as SQL for non-SQL statements.
        return unless NewRelic::Agent::Database.should_record_sql?

        agent = NewRelic::Agent.instance
        agent.transaction_sampler.notice_nosql_statement(statement, elapsed)
        nil
      end

    end
  end
end
