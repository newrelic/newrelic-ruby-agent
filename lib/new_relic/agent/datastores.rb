# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/datastores/metric_helper'

module NewRelic
  module Agent
    module Datastores

      # Add Datastore tracing to a method. This properly generates the metrics
      # for New Relic's Datastore features. It does not capture the actual
      # query content into Transaction Traces. Use wrap if you want to provide
      # that functionality.
      #
      # @param [Class] clazz the class to instrument
      #
      # @param [String, Symbol] method_name the name of instance method to
      # instrument
      #
      # @param [String] product name of your datastore for use in metric naming, e.g. "Redis"
      #
      # @param [optional,String] operation the name of operation if different
      # than the instrumented method name
      #
      # @api public
      #
      def self.trace(clazz, method_name, product, operation = method_name)
        clazz.class_eval do
          method_name_without_newrelic = "#{method_name}_without_newrelic"

          if NewRelic::Helper.instance_methods_include?(clazz, method_name) &&
             !NewRelic::Helper.instance_methods_include?(clazz, method_name_without_newrelic)

            visibility = NewRelic::Helper.instance_method_visibility(clazz, method_name)

            alias_method method_name_without_newrelic, method_name

            define_method(method_name) do |*args, &blk|
              metrics = MetricHelper.metrics_for(product, operation)
              NewRelic::Agent::MethodTracer.trace_execution_scoped(metrics) do
                send(method_name_without_newrelic, *args, &blk)
              end
            end

            send visibility, method_name
            send visibility, method_name_without_newrelic
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
      # e.g. "FauxDB"
      #
      # @param [String,Symbol] operation the name of operation (e.g. "select"),
      # often named after the method that's being instrumented.
      #
      # @param [optional, String] collection the collection name for use in
      # statement-level metrics (i.e. table or model name)
      #
      # @param [Proc,#call] notice proc or other callable to invoke after
      # running the datastore block. Receives three arguments: result of the
      # yield, list of metric names, and elapsed call time call. An example use
      # is attaching SQL to Transaction Traces at the end of a wrapped
      # datastore call.
      #
      #   note = Proc.new do |result, metrics, elapsed|
      #     NewRelic::Agent::Datastores.notice_sql(query, metrics, elapsed)
      #   end
      #
      #   NewRelic::Agent::Datastores.wrap("FauxDB", "find", "items", note) do
      #     FauxDB.find(query)
      #   end
      #
      # **NOTE: THERE ARE SECURITY CONCERNS WHEN CAPTURING SQL!**
      # New Relic's Transaction Tracing and Slow SQL features will
      # attempt to apply obfuscation to the passed queries, but it is possible
      # for a query format to be unsupported and result in exposing user
      # information.
      #
      # @api public
      #
      def self.wrap(product, operation, collection = nil, notice = nil)
        return yield unless operation

        metrics = MetricHelper.metrics_for(product, operation, collection)
        NewRelic::Agent::MethodTracer.trace_execution_scoped(metrics) do
          t0 = Time.now
          begin
            result = yield
          ensure
            if notice
              elapsed_time = (Time.now - t0).to_f
              notice.call(result, metrics, elapsed_time)
            end
          end
        end
      end

      # Wrapper for simplifying noticing SQL queries during a transaction.
      #
      #   NewRelic::Agent::Datastores.notice_sql(query, metrics, elapsed)
      #
      # @param [String] query the SQL text to be captured. Note that depending
      # on user settings, this string will be run through obfuscation, but
      # some dialects of SQL (or non-SQL queries) are not guaranteed to be
      # properly obfuscated by these routines!
      #
      # @param [Array<String>] metrics a list of the metric names from most
      # specific to least. Typically the result of
      # NewRelic::Agent::Datastores::MetricHelper#metrics_for
      #
      # @param [Float] elapsed the elapsed time during query execution
      #
      # **NOTE: THERE ARE SECURITY CONCERNS WHEN CAPTURING SQL!**
      # New Relic's Transaction Tracing and Slow SQL features will
      # attempt to apply obfuscation to the passed queries, but it is possible
      # for a query format to be unsupported and result in exposing user
      # information.
      #
      def self.notice_sql(query, metrics, elapsed)
        agent = NewRelic::Agent.instance
        agent.transaction_sampler.notice_sql(query, nil, elapsed)
        agent.sql_sampler.notice_sql(query, metrics.first, nil, elapsed)
        nil
      end

    end
  end
end
