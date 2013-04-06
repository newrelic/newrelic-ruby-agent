# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/instrumentation/transaction/pop'

# A struct holding the information required to measure a controller
# action.  This is put on the thread local.  Handles the issue of
# re-entrancy, or nested action calls.
#
# This class is not part of the public API.  Avoid making calls on it directly.
#
module NewRelic
  module Agent
    module Instrumentation
      class Transaction
        # helper module refactored out of the `pop` method
        include Pop

        attr_accessor :start_time  # A Time instance for the start time, never nil
        attr_accessor :apdex_start # A Time instance used for calculating the apdex score, which
        # might end up being @start, or it might be further upstream if
        # we can find a request header for the queue entry time
        attr_accessor(:exception, :filtered_params, :force_flag,
                      :jruby_cpu_start, :process_cpu_start, :database_metric_name)
        attr_reader :name

        # Give the current transaction a request context.  Use this to
        # get the URI and referer.  The request is interpreted loosely
        # as a Rack::Request or an ActionController::AbstractRequest.
        attr_accessor :request


        # Return the currently active transaction, or nil.  Call with +true+
        # to create a new transaction if one is not already on the thread.
        def self.current
          self.stack.last
        end

        def self.start(transaction_type, options={})
          txn = Transaction.new(transaction_type, options)
          txn.start(transaction_type)
          self.stack.push(txn)
          return txn
        end

        def self.stop(metric_name)
          txn = self.stack.pop
          txn.stop(metric_name) if txn
          return txn
        end

        def self.stack
          Thread.current[:newrelic_transaction] ||= []
        end

        def self.in_transaction?
          !self.stack.empty?
        end

        # This is the name of the model currently assigned to database
        # measurements, overriding the default.
        def self.database_metric_name
          current && current.database_metric_name
        end

        def self.referer
          current && current.referer
        end

        def self.agent
          NewRelic::Agent.instance
        end

        def self.freeze_name
          self.current && self.current.freeze_name
        end

        @@java_classes_loaded = false

        if defined? JRuby
          begin
            require 'java'
            java_import 'java.lang.management.ManagementFactory'
            java_import 'com.sun.management.OperatingSystemMXBean'
            @@java_classes_loaded = true
          rescue => e
          end
        end

        attr_reader :depth

        def initialize(type=:other, options={})
          @type = type
          @start_time = Time.now
          @jruby_cpu_start = jruby_cpu_time
          @process_cpu_start = process_cpu
          @filtered_params = options[:filtered_params] || {}
          @force_flag = options[:force]
          @request = options[:request]
          # RUBY-1059 dont think we need this
          Thread.current[:last_transaction] = self
        end

        def name=(name)
          if !@name_frozen
            @name = name
          else
            NewRelic::Agent.logger.warn("Attempted to rename transaction to #{name} after transaction name was already frozen.")
          end
        end

        def freeze_name
          @name_frozen = true
        end

        def name_frozen?
          @name_frozen
        end

        def has_parent?
          self.class.stack.size > 1
        end

        def agent
          NewRelic::Agent.instance
        end

        def transaction_sampler
          agent.transaction_sampler
        end

        def sql_sampler
          agent.sql_sampler
        end

        private :agent
        private :transaction_sampler
        private :sql_sampler

        # Indicate that we are entering a measured controller action or task.
        # Make sure you unwind every push with a pop call.
        def start(transaction_type)
          transaction_sampler.notice_first_scope_push(start_time)
          sql_sampler.notice_first_scope_push(start_time)

          agent.stats_engine.start_transaction
          agent.stats_engine.push_transaction_stats
          transaction_sampler.notice_transaction(uri, filtered_params)
          sql_sampler.notice_transaction(uri, filtered_params)
        end

        # Indicate that you don't want to keep the currently saved transaction
        # information
        def self.abort_transaction!
          current.abort_transaction! if current
        end

        # For the current web transaction, return the path of the URI minus the host part and query string, or nil.
        def uri
          @uri ||= self.class.uri_from_request(@request) unless @request.nil?
        end

        # For the current web transaction, return the full referer, minus the host string, or nil.
        def referer
          @referer ||= self.class.referer_from_request(@request)
        end

        # Call this to ensure that the current transaction is not saved
        def abort_transaction!
          transaction_sampler.ignore_transaction
        end

        # Unwind one stack level.  It knows if it's back at the outermost caller and
        # does the appropriate wrapup of the context.
        def stop(metric)
          @name ||= metric unless name_frozen?
          log_underflow if @type.nil?
          # RUBY-1059 these record metrics so need to be done before
          # the pop
          if self.class.stack.empty?
            # RUBY-1059 this one records metrics and wants to happen
            # before the transaction sampler is finished

            record_transaction_cpu if traced?
            transaction_sampler.notice_scope_empty(self)
            sql_sampler.notice_scope_empty(@name)

            # RUBY-1059 this one records metrics and wants to happen
            # after the transaction sampler is finished
            agent.stats_engine.record_gc_time if traced?
          end

          agent.stats_engine.pop_transaction_stats(@name)

          # RUBY-1059 these tear everything down so need to be done
          # after the pop
          if self.class.stack.empty?
            agent.stats_engine.end_transaction
          end
        end

        # If we have an active transaction, notice the error and increment the error metric.
        # Options:
        # * <tt>:request</tt> => Request object to get the uri and referer
        # * <tt>:uri</tt> => The request path, minus any request params or query string.
        # * <tt>:referer</tt> => The URI of the referer
        # * <tt>:metric</tt> => The metric name associated with the transaction
        # * <tt>:request_params</tt> => Request parameters, already filtered if necessary
        # * <tt>:custom_params</tt> => Custom parameters
        # Anything left over is treated as custom params

        def self.notice_error(e, options={})
          request = options.delete(:request)
          if request
            options[:referer] = referer_from_request(request)
            options[:uri] = uri_from_request(request)
          end
          if current
            current.notice_error(e, options)
          else
            agent.error_collector.notice_error(e, options)
          end
        end

        # Do not call this.  Invoke the class method instead.
        def notice_error(e, options={}) # :nodoc:
          params = custom_parameters
          options[:referer] = referer if referer
          options[:request_params] = filtered_params if filtered_params
          options[:uri] = uri if uri
          # RUBY-1059
          options[:metric] = TransactionInfo.get.transaction_name
          options.merge!(custom_parameters)
          if exception != e
            result = agent.error_collector.notice_error(e, options)
            self.exception = result if result
          end
        end

        # Add context parameters to the transaction.  This information will be passed in to errors
        # and transaction traces.  Keys and Values should be strings, numbers or date/times.
        def self.add_custom_parameters(p)
          current.add_custom_parameters(p) if current
        end

        def self.custom_parameters
          (current && current.custom_parameters) ? current.custom_parameters : {}
        end

        def self.set_user_attributes(attributes)
          current.set_user_attributes(attributes) if current
        end

        def self.user_attributes
          (current) ? current.user_attributes : {}
        end

        def record_apdex(metric_name)
          return unless recording_web_transaction? && NewRelic::Agent.is_execution_traced?
          metric_parser = NewRelic::MetricParser::MetricParser \
            .for_metric_named(metric_name)

          t = Time.now
          self.class.record_apdex(metric_parser, t - start_time, t - apdex_start, !exception.nil?)
        end

        # Yield to a block that is run with a database metric name context.  This means
        # the Database instrumentation will use this for the metric name if it does not
        # otherwise know about a model.  This is re-entrant.
        #
        # * <tt>model</tt> is the DB model class
        # * <tt>method</tt> is the name of the finder method or other method to identify the operation with.
        #
        def with_database_metric_name(model, method)
          previous = @database_metric_name
          model_name = case model
                       when Class
                         model.name
                       when String
                         model
                       else
                         model.to_s
                       end
          @database_metric_name = "ActiveRecord/#{model_name}/#{method}"
          yield
        ensure
          @database_metric_name=previous
        end

        def custom_parameters
          @custom_parameters ||= {}
        end

        def user_attributes
          @user_atrributes ||= {}
        end

        def queue_time
          @apdex_start ? @start_time - @apdex_start : 0
        end

        def add_custom_parameters(p)
          custom_parameters.merge!(p)
        end

        def set_user_attributes(attributes)
          user_attributes.merge!(attributes)
        end

        def self.recording_web_transaction?
          self.current && self.current.recording_web_transaction?
        end

        def recording_web_transaction?
          @type == :web
        end

        # Make a safe attempt to get the referer from a request object, generally successful when
        # it's a Rack request.
        def self.referer_from_request(request)
          if request && request.respond_to?(:referer)
            request.referer.to_s.split('?').first
          end
        end

        # Make a safe attempt to get the URI, without the host and query string.
        def self.uri_from_request(request)
          approximate_uri = case
                            when request.respond_to?(:fullpath) then request.fullpath
                            when request.respond_to?(:path) then request.path
                            when request.respond_to?(:request_uri) then request.request_uri
                            when request.respond_to?(:uri) then request.uri
                            when request.respond_to?(:url) then request.url
                            end
          return approximate_uri[%r{^(https?://.*?)?(/[^?]*)}, 2] || '/' if approximate_uri # '
        end

        def self.record_apdex(current_metric, action_duration, total_duration, is_error)
          agent.stats_engine.record_metrics('Apdex') do |stat|
            update_apdex(stat, total_duration, is_error)
          end
          agent.stats_engine.record_metrics(current_metric.apdex_metric_path) do |stat|
            update_apdex(stat, action_duration, is_error)
          end
        end

        # Record an apdex value for the given stat.  when `failed`
        # the apdex should be recorded as a failure regardless of duration.
        def self.update_apdex(stat, duration, failed)
          apdex_t = TransactionInfo.get.apdex_t
          duration = duration.to_f
          case
          when failed
            stat.record_apdex_f
          when duration <= apdex_t
            stat.record_apdex_s
          when duration <= 4 * apdex_t
            stat.record_apdex_t
          else
            stat.record_apdex_f
          end
          # Apdex min and max values should be initialized to the
          # current apdex_t
          stat.min_call_time = apdex_t
          stat.max_call_time = apdex_t
        end

        private

        def process_cpu
          return nil if defined? JRuby
          p = Process.times
          p.stime + p.utime
        end

        def jruby_cpu_time # :nodoc:
          return nil unless @@java_classes_loaded
          threadMBean = ManagementFactory.getThreadMXBean()
          java_utime = threadMBean.getCurrentThreadUserTime()  # ns
          -1 == java_utime ? 0.0 : java_utime/1e9
        end
      end
    end
  end
end
