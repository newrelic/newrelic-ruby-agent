# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'forwardable'
require 'new_relic/control'

# = New Relic Ruby Agent
#
# New Relic is a performance monitoring application for applications
# running in production.  For more information on New Relic please visit
# http://www.newrelic.com.
#
# The New Relic Ruby Agent can be installed in Rails applications to
# gather runtime performance metrics, traces, and errors for display
# in a Developer Mode middleware (mapped to /newrelic in your application
# server) or for monitoring and analysis at http://rpm.newrelic.com
# with just about any Ruby application.
#
# == Getting Started
# For instructions on installation and setup, see
# the README[link:./files/README_rdoc.html] file.
#
# == Using with Rack/Metal
#
# To instrument Rack middlewares or Metal apps, refer to the docs in
# NewRelic::Agent::Instrumentation::Rack.
#
# == Ruby Agent API
#
# For details on the Ruby Agent API, refer to NewRelic::Agent.
#
# == Customizing the Ruby Agent
#
# For detailed information on customizing the Ruby Agent
# please visit our {support and documentation site}[http://support.newrelic.com].
#
# @api public
#
module NewRelic
  # == Ruby Agent APIs
  # This module contains the public API methods for the Ruby Agent.
  #
  # For adding custom instrumentation to method invocations, refer to
  # the docs in the class NewRelic::Agent::MethodTracer.
  #
  # For information on how to customize the controller
  # instrumentation, or to instrument something other than Rails so
  # that high level dispatcher actions or background tasks show up as
  # first class operations in New Relic, refer to
  # NewRelic::Agent::Instrumentation::ControllerInstrumentation and
  # NewRelic::Agent::Instrumentation::ControllerInstrumentation::ClassMethods.
  #
  # Methods in this module as well as documented methods in
  # NewRelic::Agent::MethodTracer and
  # NewRelic::Agent::Instrumentation::ControllerInstrumentation are
  # available to applications.  When the agent is not enabled the
  # method implementations are stubbed into no-ops to reduce overhead.
  #
  # Methods and classes in other parts of the agent are not guaranteed
  # to be available between releases.
  #
  # Refer to the online docs at support.newrelic.com to see how to
  # access the data collected by custom instrumentation, or e-mail
  # support at New Relic for help.
  #
  # @api public
  #
  module Agent
    extend self
    extend Forwardable

    require 'new_relic/version'
    require 'new_relic/local_environment'
    require 'new_relic/metrics'
    require 'new_relic/metric_spec'
    require 'new_relic/metric_data'
    require 'new_relic/collection_helper'
    require 'new_relic/transaction_sample'
    require 'new_relic/url_rule'
    require 'new_relic/noticed_error'
    require 'new_relic/timer_lib'

    require 'new_relic/agent'
    require 'new_relic/agent/stats'
    require 'new_relic/agent/chained_call'
    require 'new_relic/agent/cross_app_monitor'
    require 'new_relic/agent/agent'
    require 'new_relic/agent/shim_agent'
    require 'new_relic/agent/method_tracer'
    require 'new_relic/agent/worker_loop'
    require 'new_relic/agent/event_loop'
    require 'new_relic/agent/stats_engine'
    require 'new_relic/agent/transaction_sampler'
    require 'new_relic/agent/sql_sampler'
    require 'new_relic/agent/commands/thread_profiler_session'
    require 'new_relic/agent/error_collector'
    require 'new_relic/agent/busy_calculator'
    require 'new_relic/agent/sampler'
    require 'new_relic/agent/database'
    require 'new_relic/agent/pipe_channel_manager'
    require 'new_relic/agent/configuration'
    require 'new_relic/agent/rules_engine'
    require 'new_relic/agent/http_clients/uri_util'
    require 'new_relic/agent/system_info'

    require 'new_relic/agent/instrumentation/controller_instrumentation'

    # this is a shim that's here only for backwards compatibility
    require 'new_relic/agent/instrumentation/metric_frame'

    require 'new_relic/agent/samplers/cpu_sampler'
    require 'new_relic/agent/samplers/memory_sampler'
    require 'new_relic/agent/samplers/object_sampler'
    require 'new_relic/agent/samplers/delayed_job_sampler'
    require 'new_relic/agent/samplers/vm_sampler'
    require 'set'
    require 'thread'
    require 'resolv'

    # An exception that is thrown by the server if the agent license is invalid.
    class LicenseException < StandardError; end

    # An exception that forces an agent to stop reporting until its mongrel is restarted.
    class ForceDisconnectException < StandardError; end

    # An exception that forces an agent to restart.
    class ForceRestartException < StandardError; end

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

    # The singleton Agent instance.  Used internally.
    def agent #:nodoc:
      return @agent if @agent
      NewRelic::Agent.logger.warn("Agent unavailable as it hasn't been started.")
      NewRelic::Agent.logger.warn(caller.join("\n"))
      nil
    end

    def agent=(new_instance)#:nodoc:
      @agent = new_instance
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

    # This needs to come after the definition of the logger method above, since
    # instantiating the config writes to the Logger.

    @config = NewRelic::Agent::Configuration::Manager.new

    attr_reader :config

    # For testing
    # Important that we don't change the instance or we orphan callbacks
    def reset_config
      @config.reset_to_defaults
    end

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
    def increment_metric(metric_name, amount=1) #THREAD_LOCAL_ACCESS
      agent.stats_engine.tl_record_unscoped_metrics(metric_name) do |stats|
        stats.increment_count(amount)
      end
    end

    # Get or create a statistics gatherer that will aggregate numerical data
    # under a metric name.
    #
    # +metric_name+ should follow a slash separated path convention. Application
    # specific metrics should begin with "Custom/".
    #
    # Return a NewRelic::Agent::Stats that accepts data
    # via calls to add_data_point(value).
    #
    # This method is deprecated in favor of record_metric and increment_metric,
    # and is not thread-safe.
    #
    # @api public
    # @deprecated
    #
    def get_stats(metric_name, use_scope=false)
      agent.stats_engine.get_stats(metric_name, use_scope)
    end

    alias get_stats_no_scope get_stats

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
      if options[:start_channel_listener]
        NewRelic::Agent::PipeChannelManager.listener.start
      end
      NewRelic::Control.instance.init_plugin({ :agent_enabled => true, :sync_startup => true }.merge(options))
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
      agent.after_fork(options)
    end

    # Clear out any data the agent has buffered but has not yet transmitted
    # to the collector.
    #
    # @api public
    def drop_buffered_data
      agent.drop_buffered_data
    end

    # Deprecated in favor of drop_buffered_data
    #
    # @api public
    # @deprecated
    def reset_stats; drop_buffered_data; end

    # Shutdown the agent.  Call this before exiting.  Sends any queued data
    # and kills the background thread.
    #
    # @api public
    #
    def shutdown(options={})
      agent.shutdown(options) if agent
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
      NewRelic::Control.instance.add_instrumentation file_pattern
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
      NewRelic::Agent::Database.set_sql_obfuscator(type, &block)
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
      state = agent.set_record_sql(false)
      begin
        yield
      ensure
        agent.set_record_sql(state)
      end
    end

    # This method disables the recording of transaction traces in the given
    # block.  See also #disable_all_tracing
    #
    # @api public
    #
    def disable_transaction_tracing
      state = agent.set_record_tt(false)
      begin
        yield
      ensure
        agent.set_record_tt(state)
      end
    end

    # This method disables the recording of the current transaction. No metrics,
    # traced errors, transaction traces, Insights events, slow SQL traces,
    # or RUM injection will happen for this transaction.
    #
    # @api public
    #
    def ignore_transaction
      txn = NewRelic::Agent::Transaction.tl_current
      txn.ignore! if txn
    end

    # This method disables the recording of Apdex metrics in the current
    # transaction.
    #
    # @api public
    #
    def ignore_apdex
      txn = NewRelic::Agent::Transaction.tl_current
      txn.ignore_apdex! if txn
    end

    # This method disables browser monitoring javascript injection in the
    # current transaction.
    #
    # @api public
    #
    def ignore_enduser
      txn = NewRelic::Agent::Transaction.tl_current
      txn.ignore_enduser! if txn
    end

    # Cancel the collection of the current transaction in progress, if
    # any.  Only affects the transaction started on this thread once
    # it has started and before it has completed.
    #
    # This method has been deprecated in favor of ignore_transaction,
    # which does what people expect this method to do.
    #
    # @api public
    # @deprecated
    #
    def abort_transaction!
      Transaction.abort_transaction!
    end

    # Yield to the block without collecting any metrics or traces in
    # any of the subsequent calls.  If executed recursively, will keep
    # track of the first entry point and turn on tracing again after
    # leaving that block.  This uses the thread local TransactionState.
    #
    # @api public
    #
    def disable_all_tracing
      agent.push_trace_execution_flag(false)
      yield
    ensure
      agent.pop_trace_execution_flag
    end

    # Record a custom event to be sent to New Relic Insights.
    # The recorded event will be buffered in memory until the next time the
    # agent sends data to New Relic's servers.
    #
    # If you want to be able to tie the information recorded via this call back
    # to the web request or background job that it happened in, you may want to
    # instead use the add_custom_parameters API call to attach attributes to
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
      if agent && NewRelic::Agent.config[:'custom_insights_events.enabled']
        agent.custom_event_aggregator.record(event_type, event_attrs)
      end
      nil
    end

    # Check to see if we are capturing metrics currently on this thread.
    def tl_is_execution_traced?
      NewRelic::Agent::TransactionState.tl_get.is_execution_traced?
    end

    # helper method to check the thread local to determine whether the
    # transaction in progress is traced or not
    def tl_is_transaction_traced?
      NewRelic::Agent::TransactionState.tl_get.is_transaction_traced?
    end

    # helper method to check the thread local to determine whether sql
    # is being recorded or not
    def tl_is_sql_recorded?
      NewRelic::Agent::TransactionState.tl_get.is_sql_recorded?
    end

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
      if block
        NewRelic::Agent::ErrorCollector.ignore_error_filter = block
      else
        NewRelic::Agent::ErrorCollector.ignore_error_filter
      end
    end

    # Record the given error.  It will be passed through the
    # #ignore_error_filter if there is one.
    #
    # * <tt>exception</tt> is the exception which will be recorded.  May also be
    #   an error message.
    # Options:
    # * <tt>:uri</tt> => The request path, minus any request params or query string.
    # * <tt>:referer</tt> => The URI of the referer
    # * <tt>:metric</tt> => The metric name associated with the transaction
    # * <tt>:request_params</tt> => Request parameters, already filtered if necessary
    # * <tt>:custom_params</tt> => Custom parameters
    #
    # Anything left over is treated as custom params.
    #
    # @api public
    #
    def notice_error(exception, options={})
      Transaction.notice_error(exception, options)
      nil # don't return a noticed error datastructure. it can only hurt.
    end

    # Add parameters to the transaction trace, Insights Transaction event, and
    # any traced errors recorded for the current transaction.
    #
    # If Browser Monitoring is enabled, and the
    # browser_monitoring.capture_attributes configuration setting is enabled,
    # these custom parameters will also be present in the RUM script injected
    # into the response body, making them available on Insights PageView events.
    #
    # @api public
    #
    def add_custom_parameters(params) #THREAD_LOCAL_ACCESS
      if params.is_a? Hash
        txn = Transaction.tl_current
        txn.add_custom_parameters(params) if txn
      else
        ::NewRelic::Agent.logger.warn("Bad argument passed to #add_custom_parameters. Expected Hash but got #{params.class}")
      end
    end

    # @deprecated
    alias add_request_parameters add_custom_parameters

    # @deprecated
    alias set_user_attributes add_custom_parameters

    # Set the name of the current running transaction.  The agent will
    # apply a reasonable default based on framework routing, but in
    # cases where this is insufficient, this can be used to manually
    # control the name of the transaction.
    # The category of transaction can be specified via the +:category+ option:
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
      Transaction.set_overriding_transaction_name(name, options[:category])
    end

    # Get the name of the current running transaction.  This is useful if you
    # want to modify the default name.
    #
    # @api public
    #
    def get_transaction_name #THREAD_LOCAL_ACCESS
      txn = Transaction.tl_current
      if txn
        namer = Instrumentation::ControllerInstrumentation::TransactionNamer
        txn.best_name.sub(Regexp.new("\\A#{Regexp.escape(namer.prefix_for_category(txn))}"), '')
      end
    end

    # Yield to a block that is run with a database metric name
    # context.  This means the Database instrumentation will use this
    # for the metric name if it does not otherwise know about a model.
    # This is re-entrant.
    #
    # * <tt>model</tt> is the DB model class
    # * <tt>method</tt> is the name of the finder method or other
    #   method to identify the operation with.
    #
    # @api public
    #
    def with_database_metric_name(model, method, &block) #THREAD_LOCAL_ACCESS
      if txn = Transaction.tl_current
        txn.with_database_metric_name(model, method, &block)
      else
        yield
      end
    end

    # Remove after 5/9/15
    def record_transaction(*args)
      NewRelic::Agent.logger.warn('This method has been deprecated, please see https://docs.newrelic.com/docs/ruby/ruby-agent-api for current API documentation.')
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
      agent.javascript_instrumentor.browser_timing_header
    end

    # In previous agent releases, this method was required for manual RUM
    # instrumentation. That work is now all done by the browser_timing_header
    # method, but this is left for compatibility.
    #
    # @api public
    # @deprecated
    #
    def browser_timing_footer
      ""
    end

    def_delegator :'NewRelic::Agent::PipeChannelManager', :register_report_channel
  end
end
