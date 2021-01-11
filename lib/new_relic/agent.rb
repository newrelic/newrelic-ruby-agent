# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require 'forwardable'

# @api public
module NewRelic
  # This module contains most of the public API methods for the Ruby Agent.
  #
  # For adding custom instrumentation to method invocations, see
  # the docs for {NewRelic::Agent::MethodTracer} and
  # {NewRelic::Agent::MethodTracer::ClassMethods}.
  #
  # For information on how to trace transactions in non-Rack contexts,
  # see {NewRelic::Agent::Instrumentation::ControllerInstrumentation}.
  #
  # For general documentation about the Ruby agent, see:
  # https://docs.newrelic.com/docs/agents/ruby-agent
  #
  # @api public
  #
  module Agent
    extend self
    extend Forwardable

    require 'new_relic/version'
    require 'new_relic/local_environment'
    require 'new_relic/metric_spec'
    require 'new_relic/metric_data'
    require 'new_relic/noticed_error'
    require 'new_relic/agent/noticible_error'
    require 'new_relic/supportability_helper'

    require 'new_relic/agent/encoding_normalizer'
    require 'new_relic/agent/stats'
    require 'new_relic/agent/chained_call'
    require 'new_relic/agent/agent'
    require 'new_relic/agent/method_tracer'
    require 'new_relic/agent/worker_loop'
    require 'new_relic/agent/event_loop'
    require 'new_relic/agent/stats_engine'
    require 'new_relic/agent/transaction_sampler'
    require 'new_relic/agent/sql_sampler'
    require 'new_relic/agent/commands/thread_profiler_session'
    require 'new_relic/agent/error_collector'
    require 'new_relic/agent/sampler'
    require 'new_relic/agent/database'
    require 'new_relic/agent/database_adapter'
    require 'new_relic/agent/datastores'
    require 'new_relic/agent/pipe_channel_manager'
    require 'new_relic/agent/configuration'
    require 'new_relic/agent/rules_engine'
    require 'new_relic/agent/http_clients/uri_util'
    require 'new_relic/agent/system_info'
    require 'new_relic/agent/external'
    require 'new_relic/agent/deprecator'
    require 'new_relic/agent/logging'
    require 'new_relic/agent/distributed_tracing'
    require 'new_relic/agent/attribute_processing'

    require 'new_relic/agent/instrumentation/controller_instrumentation'

    require 'new_relic/agent/samplers/cpu_sampler'
    require 'new_relic/agent/samplers/memory_sampler'
    require 'new_relic/agent/samplers/object_sampler'
    require 'new_relic/agent/samplers/delayed_job_sampler'
    require 'new_relic/agent/samplers/vm_sampler'
    require 'set'
    require 'thread'
    require 'resolv'

    extend NewRelic::SupportabilityHelper

    # An exception that is thrown by the server if the agent license is invalid.
    class LicenseException < StandardError; end

    # An exception that forces an agent to stop reporting until its mongrel is restarted.
    class ForceDisconnectException < StandardError; end

    # An exception that forces an agent to restart.
    class ForceRestartException < StandardError
      def message
        "#{super}, restarting."
      end
    end

    # Used to blow out of a periodic task without logging a an error, such as for routine
    # failures.
    class ServerConnectionException < StandardError; end

    # When a post is either too large or poorly formatted we should
    # drop it and not try to resend
    class UnrecoverableServerException < ServerConnectionException; end

    # An unrecoverable client-side error that prevents the agent from continuing
    class UnrecoverableAgentException < ServerConnectionException; end

    # An error while serializing data for the collector
    class SerializationError < StandardError; end

    class BackgroundLoadingError < StandardError; end

    # placeholder name used when we cannot determine a transaction's name
    UNKNOWN_METRIC = '(unknown)'.freeze

    @agent = nil
    @logger = nil
    @tracer_lock = Mutex.new
    @tracer_queue = []

    # The singleton Agent instance.  Used internally.
    def agent #:nodoc:
      return @agent if @agent
      NewRelic::Agent.logger.warn("Agent unavailable as it hasn't been started.")
      NewRelic::Agent.logger.warn(caller.join("\n"))
      nil
    end

    def agent=(new_instance)#:nodoc:
      @agent = new_instance
      add_deferred_method_tracers_now
    end

    alias instance agent #:nodoc:

    # Primary interface to logging is fronted by this accessor
    # Access via ::NewRelic::Agent.logger
    def logger
      @logger || StartupLogger.instance
    end

    def logger=(log)
      @logger = log
    end

    # A third-party class may call add_method_tracer before the agent
    # is initialized; these methods enable us to defer these calls
    # until we have started up and can process them.
    #
    def add_or_defer_method_tracer(receiver, method_name, metric_name_code, options)
      @tracer_lock.synchronize do
        if @agent
          receiver.send(:_add_method_tracer_now, method_name, metric_name_code, options)
        else
          @tracer_queue << [receiver, method_name, metric_name_code, options]
        end
      end
    end

    def add_deferred_method_tracers_now
      @tracer_lock.synchronize do
        @tracer_queue.each do |receiver, method_name, metric_name_code, options|
          receiver.send(:_add_method_tracer_now, method_name, metric_name_code, options)
        end

        @tracer_queue = []
      end
    end

    def config
      @config ||= Configuration::Manager.new
    end

    # For testing
    # Important that we don't change the instance or we orphan callbacks
    def reset_config
      config.reset_to_defaults
    end

    # @!group Recording custom metrics

    # Record a value for the given metric name.
    #
    # This method should be used to record event-based metrics such as method
    # calls that are associated with a specific duration or magnitude.
    #
    # +metric_name+ should follow a slash separated path convention. Application
    # specific metrics should begin with "Custom/".
    #
    # +value+ should be either a single Numeric value representing the duration/
    # magnitude of the event being recorded, or a Hash containing :count,
    # :total, :min, :max, and :sum_of_squares keys. The latter form is useful
    # for recording pre-aggregated metrics collected externally.
    #
    # This method is safe to use from any thread.
    #
    # @api public
    def record_metric(metric_name, value) #THREAD_LOCAL_ACCESS
      record_api_supportability_metric(:record_metric)

      return unless agent

      if value.is_a?(Hash)
        stats = NewRelic::Agent::Stats.new

        stats.call_count = value[:count] if value[:count]
        stats.total_call_time = value[:total] if value[:total]
        stats.total_exclusive_time = value[:total] if value[:total]
        stats.min_call_time = value[:min] if value[:min]
        stats.max_call_time = value[:max] if value[:max]
        stats.sum_of_squares = value[:sum_of_squares] if value[:sum_of_squares]
        value = stats
      end
      agent.stats_engine.tl_record_unscoped_metrics(metric_name, value)
    end

    # Increment a simple counter metric.
    #
    # +metric_name+ should follow a slash separated path convention. Application
    # specific metrics should begin with "Custom/".
    #
    # This method is safe to use from any thread.
    #
    # @api public

    SUPPORTABILITY_INCREMENT_METRIC = 'Supportability/API/increment_metric'.freeze

    def increment_metric(metric_name, amount=1) #THREAD_LOCAL_ACCESS
      return unless agent
      if amount == 1
        metrics = [metric_name, SUPPORTABILITY_INCREMENT_METRIC]
        agent.stats_engine.tl_record_unscoped_metrics(metrics) {|stats| stats.increment_count}
      else
        agent.stats_engine.tl_record_unscoped_metrics(metric_name) {|stats| stats.increment_count(amount)}
        agent.stats_engine.tl_record_unscoped_metrics(SUPPORTABILITY_INCREMENT_METRIC) {|stats| stats.increment_count}
      end
    end

    # @!endgroup

    # @!group Recording custom errors

    # Set a filter to be applied to errors that the Ruby Agent will
    # track.  The block should evalute to the exception to track
    # (which could be different from the original exception) or nil to
    # ignore this exception.
    #
    # The block is yielded to with the exception to filter.
    #
    # Return the new block or the existing filter Proc if no block is passed.
    #
    # @api public
    #
    def ignore_error_filter(&block)
      record_api_supportability_metric(:ignore_error_filter)

      if block
        NewRelic::Agent::ErrorCollector.ignore_error_filter = block
      else
        NewRelic::Agent::ErrorCollector.ignore_error_filter
      end
    end

    # Send an error to New Relic.
    #
    # @param [Exception] exception Error you wish to send
    # @param [Hash]      options Modify how New Relic processes the error
    # @option options [Hash]    :custom_params Custom parameters to attach to the trace
    # @option options [Boolean] :expected Only record the error trace
    #                           (do not affect error rate or Apdex status)
    # @option options [String]  :uri Request path, minus request params or query string
    #                           (usually not needed)
    # @option options [String]  :metric Metric name associated with the transaction
    #                           (usually not needed)
    #
    # Any option keys other than the ones listed here are treated as
    # <code>:custom_params</code>.
    #
    # *Note:* Previous versions of the agent allowed passing
    # <code>:request_params</code>, but those are now ignored.  If you
    # need to record the request parameters, call this method inside a
    # transaction or pass the information in
    # <code>:custom_params</code>.
    #
    # Most of the time, you do not need to specify the
    # <code>:uri</code> or <code>:metric</code> options; only pass
    # them if you are calling <code>notice_error</code> outside a
    # transaction.
    #
    # @api public
    #
    def notice_error(exception, options={})
      record_api_supportability_metric(:notice_error)

      if options.has_key?(:trace_only)
        NewRelic::Agent.logger.log_once(:warn, :trace_only_deprecated,
          'Passing the :trace_only option to NewRelic::Agent.notice_error is deprecated. Please use :expected instead.')
        options[:expected] = options.delete(:trace_only)
      end

      Transaction.notice_error(exception, options)
      nil # don't return a noticed error datastructure. it can only hurt.
    end

    # @!endgroup

    # @!group Recording custom Insights events

    # Record a custom event to be sent to New Relic Insights.
    # The recorded event will be buffered in memory until the next time the
    # agent sends data to New Relic's servers.
    #
    # If you want to be able to tie the information recorded via this call back
    # to the web request or background job that it happened in, you may want to
    # instead use the add_custom_attributes API call to attach attributes to
    # the Transaction event that will automatically be generated for the
    # request.
    #
    # A timestamp will be automatically added to the recorded event when this
    # method is called.
    #
    # @param [Symbol or String] event_type The name of the event type to record. Event
    #                           types must consist of only alphanumeric
    #                           characters, '_', ':', or ' '.
    #
    # @param [Hash] event_attrs A Hash of attributes to be attached to the event.
    #                           Keys should be strings or symbols, and values
    #                           may be strings, symbols, numeric values or
    #                           booleans.
    #
    # @api public
    #
    def record_custom_event(event_type, event_attrs)
      record_api_supportability_metric(:record_custom_event)

      if agent && NewRelic::Agent.config[:'custom_insights_events.enabled']
        agent.custom_event_aggregator.record(event_type, event_attrs)
      end

      nil
    end

    # @!endgroup

    # @!group Manual agent configuration and startup/shutdown

    # Call this to manually start the Agent in situations where the Agent does
    # not auto-start.
    #
    # When the app environment loads, so does the Agent. However, the
    # Agent will only connect to the service if a web front-end is found. If
    # you want to selectively monitor ruby processes that don't use
    # web plugins, then call this method in your code and the Agent
    # will fire up and start reporting to the service.
    #
    # Options are passed in as overrides for values in the
    # newrelic.yml, such as app_name.  In addition, the option +log+
    # will take a logger that will be used instead of the standard
    # file logger.  The setting for the newrelic.yml section to use
    # (ie, RAILS_ENV) can be overridden with an :env argument.
    #
    # @api public
    #
    def manual_start(options={})
      raise "Options must be a hash" unless Hash === options
      NewRelic::Control.instance.init_plugin({ :agent_enabled => true, :sync_startup => true }.merge(options))
      record_api_supportability_metric(:manual_start)
    end

    # Register this method as a callback for processes that fork
    # jobs.
    #
    # If the master/parent connects to the agent prior to forking the
    # agent in the forked process will use that agent_run.  Otherwise
    # the forked process will establish a new connection with the
    # server.
    #
    # Use this especially when you fork the process to run background
    # jobs or other work.  If you are doing this with a web dispatcher
    # that forks worker processes then you will need to force the
    # agent to reconnect, which it won't do by default.  Passenger and
    # Rainbows and Unicorn are already handled, nothing special needed for them.
    #
    # Options:
    # * <tt>:force_reconnect => true</tt> to force the spawned process to
    #   establish a new connection, such as when forking a long running process.
    #   The default is false--it will only connect to the server if the parent
    #   had not connected.
    # * <tt>:keep_retrying => false</tt> if we try to initiate a new
    #   connection, this tells me to only try it once so this method returns
    #   quickly if there is some kind of latency with the server.
    #
    # @api public
    #
    def after_fork(options={})
      record_api_supportability_metric(:after_fork)
      agent.after_fork(options) if agent
    end

    # Shutdown the agent.  Call this before exiting.  Sends any queued data
    # and kills the background thread.
    #
    # @param options [Hash] Unused options Hash, for back compatibility only
    #
    # @api public
    #
    def shutdown(options={})
      record_api_supportability_metric(:shutdown)
      agent.shutdown if agent
    end

    # Clear out any data the agent has buffered but has not yet transmitted
    # to the collector.
    #
    # @api public
    def drop_buffered_data
      agent.drop_buffered_data if agent
      record_api_supportability_metric(:drop_buffered_data)
    end

    # Add instrumentation files to the agent.  The argument should be
    # a glob matching ruby scripts which will be executed at the time
    # instrumentation is loaded.  Since instrumentation is not loaded
    # when the agent is not running it's better to use this method to
    # register instrumentation than just loading the files directly,
    # although that probably also works.
    #
    # @api public
    #
    def add_instrumentation(file_pattern)
      record_api_supportability_metric(:add_instrumentation)
      NewRelic::Control.instance.add_instrumentation file_pattern
    end

    # Require agent testing helper methods
    #
    # @api public
    def require_test_helper
      record_api_supportability_metric(:require_test_helper)
      require File.expand_path('../../../test/agent_helper', __FILE__)
    end

    # This method sets the block sent to this method as a sql
    # obfuscator.  The block will be called with a single String SQL
    # statement to obfuscate.  The method must return the obfuscated
    # String SQL.  If chaining of obfuscators is required, use type =
    # :before or :after
    #
    # type = :before, :replace, :after
    #
    # Example:
    #
    #    NewRelic::Agent.set_sql_obfuscator(:replace) do |sql|
    #       my_obfuscator(sql)
    #    end
    #
    # @api public
    #
    def set_sql_obfuscator(type = :replace, &block)
      record_api_supportability_metric(:set_sql_obfuscator)
      NewRelic::Agent::Database.set_sql_obfuscator(type, &block)
    end

    # @!endgroup

    # @!group Ignoring or excluding data

    # This method disables the recording of the current transaction. No metrics,
    # traced errors, transaction traces, Insights events, slow SQL traces,
    # or RUM injection will happen for this transaction.
    #
    # @api public
    #
    def ignore_transaction
      record_api_supportability_metric(:ignore_transaction)
      txn = NewRelic::Agent::Transaction.tl_current
      txn.ignore! if txn
    end

    # This method disables the recording of Apdex metrics in the current
    # transaction.
    #
    # @api public
    #
    def ignore_apdex
      record_api_supportability_metric(:ignore_apdex)
      txn = NewRelic::Agent::Transaction.tl_current
      txn.ignore_apdex! if txn
    end

    # This method disables browser monitoring javascript injection in the
    # current transaction.
    #
    # @api public
    #
    def ignore_enduser
      record_api_supportability_metric(:ignore_enduser)
      txn = NewRelic::Agent::Transaction.tl_current
      txn.ignore_enduser! if txn
    end

    # Yield to the block without collecting any metrics or traces in
    # any of the subsequent calls.  If executed recursively, will keep
    # track of the first entry point and turn on tracing again after
    # leaving that block.  This uses the thread local Tracer::State.
    #
    # @api public
    #
    def disable_all_tracing
      record_api_supportability_metric(:disable_all_tracing)

      return yield unless agent

      begin
        agent.push_trace_execution_flag(false)
        yield
      ensure
        agent.pop_trace_execution_flag
      end
    end

    # This method disables the recording of transaction traces in the given
    # block.  See also #disable_all_tracing
    #
    # @api public
    #
    def disable_transaction_tracing
      Deprecator.deprecate :disable_transaction_tracing,
                           'disable_all_tracing or ignore_transaction'
      record_api_supportability_metric(:disable_transaction_tracing)
      yield
    end

    # This method sets the state of sql recording in the transaction
    # sampler feature. Within the given block, no sql will be recorded
    #
    # usage:
    #
    #   NewRelic::Agent.disable_sql_recording do
    #     ...
    #   end
    #
    # @api public
    #
    def disable_sql_recording
      record_api_supportability_metric(:disable_sql_recording)

      return yield unless agent

      state = agent.set_record_sql(false)
      begin
        yield
      ensure
        agent.set_record_sql(state)
      end
    end

    # @!endgroup

    # Check to see if we are capturing metrics currently on this thread.
    def tl_is_execution_traced?
      NewRelic::Agent::Tracer.state.is_execution_traced?
    end

    # helper method to check the thread local to determine whether sql
    # is being recorded or not
    def tl_is_sql_recorded?
      NewRelic::Agent::Tracer.state.is_sql_recorded?
    end

    # @!group Adding custom attributes to traces

    # Add attributes to the transaction trace, Insights Transaction event, and
    # any traced errors recorded for the current transaction.
    #
    # If Browser Monitoring is enabled, and the
    # browser_monitoring.attributes.enabled configuration setting is true,
    # these custom attributes will also be present in the script injected into
    # the response body, making them available on Insights PageView events.
    #
    #
    # @param [Hash] params      A Hash of attributes to be attached to the transaction event.
    #                           Keys should be strings or symbols, and values
    #                           may be strings, symbols, numeric values or
    #                           booleans.
    #
    # @api public
    #
    def add_custom_attributes(params) #THREAD_LOCAL_ACCESS
      record_api_supportability_metric(:add_custom_attributes)

      if params.is_a? Hash
        txn = Transaction.tl_current
        txn.add_custom_attributes(params) if txn

        segment = ::NewRelic::Agent::Tracer.current_segment
        if segment
          # Make sure not to override existing segment-level custom attributes
          segment_custom_keys = segment.attributes.custom_attributes.keys.map(&:to_sym)
          segment.add_custom_attributes(params.reject { |k, _v| segment_custom_keys.include?(k.to_sym) })
        end
      else
        ::NewRelic::Agent.logger.warn("Bad argument passed to #add_custom_attributes. Expected Hash but got #{params.class}")
      end
    end

    # Add custom attributes to the span event for the current span. Attributes will be visible on spans in the
    # New Relic Distributed Tracing UI and on span events in New Relic Insights.
    #
    # Custom attributes will not be transmitted when +high_security+ setting is enabled or
    # +custom_attributes+ setting is disabled.
    #
    # @param [Hash] params      A Hash of attributes to be attached to the span event.
    #                           Keys should be strings or symbols, and values
    #                           may be strings, symbols, numeric values or
    #                           booleans.
    #
    # @see https://docs.newrelic.com/docs/using-new-relic/welcome-new-relic/get-started/glossary#span
    # @api public
    def add_custom_span_attributes params
      record_api_supportability_metric :add_custom_span_attributes

      if params.is_a? Hash
        if segment = NewRelic::Agent::Tracer.current_segment
          segment.add_custom_attributes params
        end
      else
        ::NewRelic::Agent.logger.warn "Bad argument passed to #add_custom_span_attributes. Expected Hash but got #{params.class}"
      end
    end

    # @!endgroup

    # @!group Transaction naming

    # Set the name of the current running transaction.  The agent will
    # apply a reasonable default based on framework routing, but in
    # cases where this is insufficient, this can be used to manually
    # control the name of the transaction.
    #
    # The category of transaction can be specified via the +:category+ option.
    # The following are the only valid categories:
    #
    # * <tt>:category => :controller</tt> indicates that this is a
    #   controller action and will appear with all the other actions.
    # * <tt>:category => :task</tt> indicates that this is a
    #   background task and will show up in New Relic with other background
    #   tasks instead of in the controllers list
    # * <tt>:category => :middleware</tt> if you are instrumenting a rack
    #   middleware call.  The <tt>:name</tt> is optional, useful if you
    #   have more than one potential transaction in the #call.
    # * <tt>:category => :uri</tt> indicates that this is a
    #   web transaction whose name is a normalized URI, where  'normalized'
    #   means the URI does not have any elements with data in them such
    #   as in many REST URIs.
    #
    # The default category is the same as the running transaction.
    #
    # @api public
    #
    def set_transaction_name(name, options={})
      record_api_supportability_metric(:set_transaction_name)
      Transaction.set_overriding_transaction_name(name, options[:category])
    end

    # Get the name of the current running transaction.  This is useful if you
    # want to modify the default name.
    #
    # @api public
    #
    def get_transaction_name #THREAD_LOCAL_ACCESS
      record_api_supportability_metric(:get_transaction_name)

      txn = Transaction.tl_current
      if txn
        namer = Instrumentation::ControllerInstrumentation::TransactionNamer
        txn.best_name.sub(Regexp.new("\\A#{Regexp.escape(namer.prefix_for_category(txn))}"), '')
      end
    end

    # @!endgroup

    # Yield to a block that is run with a database metric name context.  This means
    # the Database instrumentation will use this for the metric name if it does not
    # otherwise know about a model.  This is re-entrant.
    #
    # @param [String,Class,#to_s] model the DB model class
    #
    # @param [String] method the name of the finder method or other method to
    # identify the operation with.
    #
    def with_database_metric_name(model, method = nil, product = nil, &block)
      if txn = Tracer.current_transaction
        txn.with_database_metric_name(model, method, product, &block)
      else
        yield
      end
    end

    # Subscribe to events of +event_type+, calling the given +handler+
    # when one is sent.
    def subscribe(event_type, &handler)
      agent.events.subscribe( event_type, &handler )
    end

    # Fire an event of the specified +event_type+, passing it an the given +args+
    # to any registered handlers.
    def notify(event_type, *args)
      agent.events.notify( event_type, *args )
    rescue
      NewRelic::Agent.logger.debug "Ignoring exception during %p event notification" % [event_type]
    end

    # @!group Trace and Entity metadata

    TRACE_ID_KEY = 'trace.id'.freeze
    SPAN_ID_KEY = 'span.id'.freeze
    ENTITY_NAME_KEY = 'entity.name'.freeze
    ENTITY_TYPE_KEY = 'entity.type'.freeze
    ENTITY_GUID_KEY = 'entity.guid'.freeze
    HOSTNAME_KEY = 'hostname'.freeze

    ENTITY_TYPE = 'SERVICE'.freeze

    # Returns a new hash containing trace and entity metadata that can be used
    # to relate data to a trace or to an entity in APM.
    #
    # This hash includes:
    # * trace.id    - The current trace id, if there is a current trace id. This
    #   value may be omitted.
    # * span.id     - The current span id, if there is a current span.  This
    #   value may be omitted.
    # * entity.name - The name of the current application. This is read from
    #   the +app_name+ key in your config.  If there are multiple application
    #   names, the first one is used.
    # * entity.type - The entity type is hardcoded to the string +'SERVICE'+.
    # * entity.guid - The guid of the current entity.
    # * hostname    - The fully qualified hostname.
    #
    # @api public
    def linking_metadata
      metadata = Hash.new
      metadata[ENTITY_NAME_KEY] = config[:app_name][0]
      metadata[ENTITY_TYPE_KEY] = ENTITY_TYPE
      metadata[HOSTNAME_KEY] = Hostname.get

      if entity_guid = config[:entity_guid]
        metadata[ENTITY_GUID_KEY] = entity_guid
      end

      if trace_id = Tracer.current_trace_id
        metadata[TRACE_ID_KEY] = trace_id
      end
      if span_id = Tracer.current_span_id
        metadata[SPAN_ID_KEY] = span_id
      end
      metadata
    end

    #@!endgroup

    # @!group Manual browser monitoring configuration

    # This method returns a string suitable for inclusion in a page - known as
    # 'manual instrumentation' for Real User Monitoring. Can return either a
    # script tag with associated javascript, or in the case of disabled Real
    # User Monitoring, an empty string
    #
    # This is the header string - it should be placed as high in the page as is
    # reasonably possible - that is, before any style or javascript inclusions,
    # but after any header-related meta tags
    #
    # In previous agents there was a corresponding footer required, but all the
    # work is now done by this single method.
    #
    # @api public
    #
    def browser_timing_header
      record_api_supportability_metric(:browser_timing_header)

      return "" unless agent
      agent.javascript_instrumentor.browser_timing_header
    end

    # @!endgroup

    def_delegator :'NewRelic::Agent::PipeChannelManager', :register_report_channel
  end
end
