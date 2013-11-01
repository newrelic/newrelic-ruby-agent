# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'socket'
require 'net/https'
require 'net/http'
require 'logger'
require 'zlib'
require 'stringio'
require 'new_relic/agent/sampled_buffer'
require 'new_relic/agent/autostart'
require 'new_relic/agent/new_relic_service'
require 'new_relic/agent/pipe_service'
require 'new_relic/agent/configuration/manager'
require 'new_relic/agent/database'
require 'new_relic/agent/commands/agent_command_router'
require 'new_relic/agent/event_listener'
require 'new_relic/agent/cross_app_monitor'
require 'new_relic/agent/request_sampler'
require 'new_relic/agent/sampler_collection'
require 'new_relic/environment_report'

module NewRelic
  module Agent

    # The Agent is a singleton that is instantiated when the plugin is
    # activated.  It collects performance data from ruby applications
    # in realtime as the application runs, and periodically sends that
    # data to the NewRelic server.
    class Agent
      extend NewRelic::Agent::Configuration::Instance

      def initialize
        # FIXME: temporary work around for RUBY-839
        # This should be handled with a configuration callback
        if Agent.config[:monitor_mode]
          @service = NewRelic::Agent::NewRelicService.new
        end

        @launch_time = Time.now

        @events                = NewRelic::Agent::EventListener.new
        @stats_engine          = NewRelic::Agent::StatsEngine.new
        @transaction_sampler   = NewRelic::Agent::TransactionSampler.new
        @sql_sampler           = NewRelic::Agent::SqlSampler.new
        @agent_command_router  = NewRelic::Agent::Commands::AgentCommandRouter.new(@events)
        @cross_app_monitor     = NewRelic::Agent::CrossAppMonitor.new(@events)
        @error_collector       = NewRelic::Agent::ErrorCollector.new
        @transaction_rules     = NewRelic::Agent::RulesEngine.new
        @request_sampler       = NewRelic::Agent::RequestSampler.new(@events)
        @harvest_samplers      = NewRelic::Agent::SamplerCollection.new(@events)

        @connect_state      = :pending
        @connect_attempts   = 0
        @environment_report = nil

        @harvest_lock = Mutex.new
        @obfuscator = lambda {|sql| NewRelic::Agent::Database.default_sql_obfuscator(sql) }
      end

      # contains all the class-level methods for NewRelic::Agent::Agent
      module ClassMethods
        # Should only be called by NewRelic::Control - returns a
        # memoized singleton instance of the agent, creating one if needed
        def instance
          @instance ||= self.new
        end
      end

      # Holds all the methods defined on NewRelic::Agent::Agent
      # instances
      module InstanceMethods

        # holds a proc that is used to obfuscate sql statements
        attr_reader :obfuscator
        # the statistics engine that holds all the timeslice data
        attr_reader :stats_engine
        # the transaction sampler that handles recording transactions
        attr_reader :transaction_sampler
        attr_reader :sql_sampler
        # manages agent commands we receive from the collector, and the handlers
        attr_reader :agent_command_router
        # error collector is a simple collection of recorded errors
        attr_reader :error_collector
        attr_reader :harvest_samplers
        # whether we should record raw, obfuscated, or no sql
        attr_reader :record_sql
        # a configuration for the Real User Monitoring system -
        # handles things like static setup of the header for inclusion
        # into pages
        attr_reader :beacon_configuration
        # cross application tracing ids and encoding
        attr_reader :cross_process_id
        attr_reader :cross_app_encoding_bytes
        attr_reader :cross_app_monitor
        # service for communicating with collector
        attr_accessor :service
        # Global events dispatcher. This will provides our primary mechanism
        # for agent-wide events, such as finishing configuration, error notification
        # and request before/after from Rack.
        attr_reader :events
        # Transaction and metric renaming rules as provided by the
        # collector on connect.  The former are applied during txns,
        # the latter during harvest.
        attr_reader :transaction_rules
        attr_reader :harvest_lock

        # fakes out a transaction that did not happen in this process
        # by creating apdex, summary metrics, and recording statistics
        # for the transaction
        #
        # This method is *deprecated* - it may be removed in future
        # versions of the agent
        def record_transaction(duration_seconds, options={})
          is_error = options['is_error'] || options['error_message'] || options['exception']
          metric = options['metric']
          metric ||= options['uri'] # normalize this with url rules
          raise "metric or uri arguments required" unless metric
          metric_info = NewRelic::MetricParser::MetricParser.for_metric_named(metric)

          if metric_info.is_web_transaction?
            NewRelic::Agent::Transaction.record_apdex(metric_info, duration_seconds, duration_seconds, is_error)
          end
          metrics = metric_info.summary_metrics

          metrics << metric
          metrics.each do |name|
            NewRelic::Agent.record_metric(name, duration_seconds)
          end

          if is_error
            if options['exception']
              e = options['exception']
            elsif options['error_message']
              e = StandardError.new options['error_message']
            else
              e = StandardError.new 'Unknown Error'
            end
            error_collector.notice_error e, :uri => options['uri'], :metric => metric
          end
          # busy time ?
        end

        # This method should be called in a forked process after a fork.
        # It assumes the parent process initialized the agent, but does
        # not assume the agent started.
        #
        # The call is idempotent, but not re-entrant.
        #
        # * It clears any metrics carried over from the parent process
        # * Restarts the sampler thread if necessary
        # * Initiates a new agent run and worker loop unless that was done
        #   in the parent process and +:force_reconnect+ is not true
        #
        # Options:
        # * <tt>:force_reconnect => true</tt> to force the spawned process to
        #   establish a new connection, such as when forking a long running process.
        #   The default is false--it will only connect to the server if the parent
        #   had not connected.
        # * <tt>:keep_retrying => false</tt> if we try to initiate a new
        #   connection, this tells me to only try it once so this method returns
        #   quickly if there is some kind of latency with the server.
        def after_fork(options={})
          Agent.config.apply_config(NewRelic::Agent::Configuration::ManualSource.new(options), 1)

          if channel_id = options[:report_to_channel]
            @service = NewRelic::Agent::PipeService.new(channel_id)
            if connected?
              @connected_pid = $$
            else
              ::NewRelic::Agent.logger.debug("Child process #{$$} not reporting to non-connected parent.")
              @service.shutdown(Time.now)
              disconnect
            end
          end

          return if !Agent.config[:agent_enabled] ||
            !Agent.config[:monitor_mode] ||
            disconnected? ||
            @worker_thread && @worker_thread.alive?

          ::NewRelic::Agent.logger.debug "Starting the worker thread in #{$$} after forking."

          reset_objects_with_locks

          # Clear out stats that are left over from parent process
          reset_stats

          generate_environment_report unless @service.is_a?(NewRelic::Agent::PipeService)
          start_worker_thread(options)
        end

        # True if we have initialized and completed 'start'
        def started?
          @started
        end

        # Attempt a graceful shutdown of the agent, running the worker
        # loop if it exists and is running.
        #
        # Options:
        # :force_send  => (true/false) # force the agent to send data
        def shutdown(options={})
          run_loop_before_exit = Agent.config[:force_send]
          return if not started?
          if @worker_loop
            @worker_loop.run_task if run_loop_before_exit
            @worker_loop.stop
          end

          ::NewRelic::Agent.logger.info "Starting Agent shutdown"

          # if litespeed, then ignore all future SIGUSR1 - it's
          # litespeed trying to shut us down
          if Agent.config[:dispatcher] == :litespeed
            Signal.trap("SIGUSR1", "IGNORE")
            Signal.trap("SIGTERM", "IGNORE")
          end

          begin
            NewRelic::Agent.disable_all_tracing do
              graceful_disconnect
            end
          rescue => e
            ::NewRelic::Agent.logger.error e
          end
          NewRelic::Agent.config.remove_config do |config|
            config.class == NewRelic::Agent::Configuration::ManualSource ||
              config.class == NewRelic::Agent::Configuration::ServerSource
          end
          @started = nil
          Control.reset
        end

        # Tells the statistics engine we are starting a new transaction
        def start_transaction
          @stats_engine.start_transaction
        end

        # Tells the statistics engine we are ending a transaction
        def end_transaction
          @stats_engine.end_transaction
        end

        # Sets a thread local variable as to whether we should or
        # should not record sql in the current thread. Returns the
        # previous value, if there is one
        def set_record_sql(should_record)
          prev = TransactionState.get.record_sql
          TransactionState.get.record_sql = should_record
          prev.nil? || prev
        end

        # Sets a thread local variable as to whether we should or
        # should not record transaction traces in the current
        # thread. Returns the previous value, if there is one
        def set_record_tt(should_record)
          prev = TransactionState.get.record_tt
          TransactionState.get.record_tt = should_record
          prev.nil? || prev
        end

        # Push flag indicating whether we should be tracing in this
        # thread. This uses a stack which allows us to disable tracing
        # children of a transaction without affecting the tracing of
        # the whole transaction
        def push_trace_execution_flag(should_trace=false)
          TransactionState.get.push_traced(should_trace)
        end

        # Pop the current trace execution status.  Restore trace execution status
        # to what it was before we pushed the current flag.
        def pop_trace_execution_flag
          TransactionState.get.pop_traced
        end

        # Herein lies the corpse of the former 'start' method. May
        # its unmatched flog score rest in pieces.
        module Start
          # Check whether we have already started, which is an error condition
          def already_started?
            if started?
              ::NewRelic::Agent.logger.error("Agent Started Already!")
              true
            end
          end

          # The agent is disabled when it is not force enabled by the
          # 'agent_enabled' option (e.g. in a manual start), or
          # enabled normally through the configuration file
          def disabled?
            !Agent.config[:agent_enabled]
          end

          # Log startup information that we almost always want to know
          def log_startup
            log_environment
            log_dispatcher
            log_app_name
          end

          # Log the environment the app thinks it's running in.
          # Useful in debugging, as this is the key for config YAML lookups.
          def log_environment
            ::NewRelic::Agent.logger.info "Environment: #{NewRelic::Control.instance.env}"
          end

          # Logs the dispatcher to the log file to assist with
          # debugging. When no debugger is present, logs this fact to
          # assist with proper dispatcher detection
          def log_dispatcher
            dispatcher_name = Agent.config[:dispatcher].to_s

            if dispatcher_name.empty?
              ::NewRelic::Agent.logger.info 'No known dispatcher detected.'
            else
              ::NewRelic::Agent.logger.info "Dispatcher: #{dispatcher_name}"
            end
          end

          def log_app_name
            ::NewRelic::Agent.logger.info "Application: #{Agent.config.app_names.join(", ")}"
          end

          # Logs the configured application names
          def app_name_configured?
            names = Agent.config.app_names
            return names.respond_to?(:any?) && names.any?
          end

          # Connecting in the foreground blocks further startup of the
          # agent until we have a connection - useful in cases where
          # you're trying to log a very-short-running process and want
          # to get statistics from before a server connection
          # (typically 20 seconds) exists
          def connect_in_foreground
            NewRelic::Agent.disable_all_tracing { connect(:keep_retrying => false) }
          end

          # If we're using sinatra, old versions run in an at_exit
          # block so we should probably know that
          def using_sinatra?
            defined?(Sinatra::Application)
          end

          # we should not set an at_exit block if people are using
          # these as they don't do standard at_exit behavior per MRI/YARV
          def weird_ruby?
            NewRelic::LanguageSupport.using_engine?('rbx') ||
              NewRelic::LanguageSupport.using_engine?('jruby') ||
              using_sinatra?
          end

          # Installs our exit handler, which exploits the weird
          # behavior of at_exit blocks to make sure it runs last, by
          # doing an at_exit within an at_exit block.
          def install_exit_handler
            if Agent.config[:send_data_on_exit] && !weird_ruby?
              at_exit do
                # Workaround for MRI 1.9 bug that loses exit codes in at_exit blocks.
                # This is necessary to get correct exit codes for the agent's
                # test suites.
                # http://bugs.ruby-lang.org/issues/5218
                if defined?(RUBY_ENGINE) && RUBY_ENGINE == "ruby" && RUBY_VERSION.match(/^1\.9/)
                  exit_status = $!.status if $!.is_a?(SystemExit)
                  shutdown
                  exit exit_status if exit_status
                else
                  shutdown
                end
              end
            end
          end

          # Classy logging of the agent version and the current pid,
          # so we can disambiguate processes in the log file and make
          # sure they're running a reasonable version
          def log_version_and_pid
            ::NewRelic::Agent.logger.debug "New Relic Ruby Agent #{NewRelic::VERSION::STRING} Initialized: pid = #{$$}"
          end

          # Warn the user if they have configured their agent not to
          # send data, that way we can see this clearly in the log file
          def monitoring?
            if Agent.config[:monitor_mode]
              true
            else
              ::NewRelic::Agent.logger.warn('Agent configured not to send data in this environment.')
              false
            end
          end

          # Tell the user when the license key is missing so they can
          # fix it by adding it to the file
          def has_license_key?
            if Agent.config[:license_key] && Agent.config[:license_key].length > 0
              true
            else
              ::NewRelic::Agent.logger.warn("No license key found in newrelic.yml config. " +
                "This often means your newrelic.yml is missing a section for the running environment '#{NewRelic::Control.instance.env}'")
              false
            end
          end

          # A correct license key exists and is of the proper length
          def has_correct_license_key?
            has_license_key? && correct_license_length
          end

          # A license key is an arbitrary 40 character string,
          # usually looks something like a SHA1 hash
          def correct_license_length
            key = Agent.config[:license_key]

            if key.length == 40
              true
            else
              ::NewRelic::Agent.logger.error("Invalid license key: #{key}")
              false
            end
          end

          # If we're using a dispatcher that forks before serving
          # requests, we need to wait until the children are forked
          # before connecting, otherwise the parent process sends odd data
          def using_forking_dispatcher?
            if [:passenger, :rainbows, :unicorn].include? Agent.config[:dispatcher]
              ::NewRelic::Agent.logger.info 'Connecting workers after forking.'
              true
            else
              false
            end
          end

          # Return true if we're using resque and it hasn't had a chance to (potentially)
          # daemonize itself. This avoids hanging when there's a Thread started
          # before Resque calls Process.daemon (Jira RUBY-857)
          def defer_for_resque?
            NewRelic::Agent.config[:dispatcher] == :resque &&
              NewRelic::LanguageSupport.can_fork? &&
              !NewRelic::Agent::PipeChannelManager.listener.started?
          end

          # Sanity-check the agent configuration and start the agent,
          # setting up the worker thread and the exit handler to shut
          # down the agent
          def check_config_and_start_agent
            return unless monitoring? && has_correct_license_key?
            return if using_forking_dispatcher?
            generate_environment_report
            connect_in_foreground if Agent.config[:sync_startup]
            start_worker_thread
            install_exit_handler
          end
        end

        include Start

        def defer_for_delayed_job?
          NewRelic::Agent.config[:dispatcher] == :delayed_job &&
            !NewRelic::DelayedJobInjection.worker_name
        end

        # Check to see if the agent should start, returning +true+ if it should.
        def agent_should_start?
          return false if already_started? || disabled?

          if defer_for_delayed_job?
            ::NewRelic::Agent.logger.debug "Deferring startup for DelayedJob"
            return false
          end

          if defer_for_resque?
            ::NewRelic::Agent.logger.debug "Deferring startup for Resque in case it daemonizes"
            return false
          end

          unless app_name_configured?
            NewRelic::Agent.logger.error "No application name configured.",
              "The Agent cannot start without at least one. Please check your ",
              "newrelic.yml and ensure that it is valid and has at least one ",
              "value set for app_name in the #{NewRelic::Control.instance.env} ",
              "environment."
            return false
          end

          return true
        end

        # Logs a bunch of data and starts the agent, if needed
        def start
          return unless agent_should_start?

          @started = true
          @local_host = determine_host
          log_startup
          check_config_and_start_agent
          log_version_and_pid
        end

        # Clear out the metric data, errors, and transaction traces,
        # making sure the agent is in a fresh state
        def reset_stats
          @stats_engine.reset_stats
          @error_collector.reset!
          @transaction_sampler.reset!
          @request_sampler.reset!
          @sql_sampler.reset!
          @launch_time = Time.now
        end

        # Clear out state for any objects that we know lock from our parents
        # This is necessary for cases where we're in a forked child and Ruby
        # might be holding locks for background thread that aren't there anymore.
        def reset_objects_with_locks
          @stats_engine = NewRelic::Agent::StatsEngine.new
          reset_harvest_locks
        end

        def add_harvest_sampler(subclass)
          @harvest_samplers.add_sampler(subclass)
        end

        private

        # All of this module used to be contained in the
        # start_worker_thread method - this is an artifact of
        # refactoring and can be moved, renamed, etc at will
        module StartWorkerThread
          # logs info about the worker loop so users can see when the
          # agent actually begins running in the background
          def log_worker_loop_start
            ::NewRelic::Agent.logger.debug "Reporting performance data every #{Agent.config[:data_report_period]} seconds."
            ::NewRelic::Agent.logger.debug "Running worker loop"
          end

          # Synchronize with the harvest loop. If the harvest thread has taken
          # a lock (DNS lookups, backticks, agent-owned locks, etc), and we
          # fork while locked, this can deadlock child processes. For more
          # details, see https://github.com/resque/resque/issues/1101
          def synchronize_with_harvest
            harvest_lock.synchronize do
              yield
            end
          end

          # Some forking cases (like Resque) end up with harvest lock from the
          # parent process orphaned in the child. Let it go before we proceed.
          def reset_harvest_locks
            return if harvest_lock.nil?

            harvest_lock.unlock if harvest_lock.locked?
          end

          # Creates the worker loop and loads it with the instructions
          # it should run every @report_period seconds
          def create_and_run_worker_loop
            @worker_loop = WorkerLoop.new
            @worker_loop.run(Agent.config[:data_report_period]) do
              transmit_data
            end
          end

          # Handles the case where the server tells us to restart -
          # this clears the data, clears connection attempts, and
          # waits a while to reconnect.
          def handle_force_restart(error)
            ::NewRelic::Agent.logger.debug error.message
            reset_stats
            @service.reset_metric_id_cache if @service
            @connect_state = :pending
            sleep 30
          end

          # when a disconnect is requested, stop the current thread, which
          # is the worker thread that gathers data and talks to the
          # server.
          def handle_force_disconnect(error)
            ::NewRelic::Agent.logger.warn "New Relic forced this agent to disconnect (#{error.message})"
            disconnect
          end

          # Handles an unknown error in the worker thread by logging
          # it and disconnecting the agent, since we are now in an
          # unknown state.
          def handle_other_error(error)
            ::NewRelic::Agent.logger.error "Unhandled error in worker thread, disconnecting this agent process:"
            # These errors are fatal (that is, they will prevent the agent from
            # reporting entirely), so we really want backtraces when they happen
            ::NewRelic::Agent.logger.log_exception(:error, error)
            disconnect
          end

          # a wrapper method to handle all the errors that can happen
          # in the connection and worker thread system. This
          # guarantees a no-throw from the background thread.
          def catch_errors
            yield
          rescue NewRelic::Agent::ForceRestartException => e
            handle_force_restart(e)
            retry
          rescue NewRelic::Agent::ForceDisconnectException => e
            handle_force_disconnect(e)
          rescue => e
            handle_other_error(e)
          end

          # This is the method that is run in a new thread in order to
          # background the harvesting and sending of data during the
          # normal operation of the agent.
          #
          # Takes connection options that determine how we should
          # connect to the server, and loops endlessly - typically we
          # never return from this method unless we're shutting down
          # the agent
          def deferred_work!(connection_options)
            catch_errors do
              NewRelic::Agent.disable_all_tracing do
                # We try to connect.  If this returns false that means
                # the server rejected us for a licensing reason and we should
                # just exit the thread.  If it returns nil
                # that means it didn't try to connect because we're in the master.
                connect(connection_options)
                if connected?
                  log_worker_loop_start
                  create_and_run_worker_loop
                  # never reaches here unless there is a problem or
                  # the agent is exiting
                else
                  ::NewRelic::Agent.logger.debug "No connection.  Worker thread ending."
                end
              end
            end
          end
        end
        include StartWorkerThread

        # Try to launch the worker thread and connect to the server.
        #
        # See #connect for a description of connection_options.
        def start_worker_thread(connection_options = {})
          disable = NewRelic::Agent.config[:disable_harvest_thread]
          if disable
            NewRelic::Agent.logger.info "Not starting Ruby Agent worker thread because :disable_harvest_thread is #{disable}"
            return
          end

          ::NewRelic::Agent.logger.debug "Creating Ruby Agent worker thread."
          @worker_thread = NewRelic::Agent::Threading::AgentThread.new('Worker Loop') do
            deferred_work!(connection_options)
          end
        end

        # A shorthand for NewRelic::Control.instance
        def control
          NewRelic::Control.instance
        end

        # This module is an artifact of a refactoring of the connect
        # method - all of its methods are used in that context, so it
        # can be refactored at will. It should be fully tested
        module Connect
          # number of attempts we've made to contact the server
          attr_accessor :connect_attempts

          # Disconnect just sets connected to false, which prevents
          # the agent from trying to connect again
          def disconnect
            @connect_state = :disconnected
            true
          end

          def connected?
            @connect_state == :connected
          end

          def disconnected?
            @connect_state == :disconnected
          end

          # Don't connect if we're already connected, or if we tried to connect
          # and were rejected with prejudice because of a license issue, unless
          # we're forced to by force_reconnect.
          def should_connect?(force=false)
            force || (!connected? && !disconnected?)
          end

          # Retry period is a minute for each failed attempt that
          # we've made. This should probably do some sort of sane TCP
          # backoff to prevent hammering the server, but a minute for
          # each attempt seems to work reasonably well.
          def connect_retry_period
            [600, connect_attempts * 60].min
          end

          def note_connect_failure
            self.connect_attempts += 1
          end

          # When we have a problem connecting to the server, we need
          # to tell the user what happened, since this is not an error
          # we can handle gracefully.
          def log_error(error)
            ::NewRelic::Agent.logger.error "Error establishing connection with New Relic Service at #{control.server}:", error
          end

          # When the server sends us an error with the license key, we
          # want to tell the user that something went wrong, and let
          # them know where to go to get a valid license key
          #
          # After this runs, it disconnects the agent so that it will
          # no longer try to connect to the server, saving the
          # application and the server load
          def handle_license_error(error)
            ::NewRelic::Agent.logger.error( \
              error.message, \
              "Visit NewRelic.com to obtain a valid license key, or to upgrade your account.")
            disconnect
          end

          def handle_unrecoverable_agent_error(error)
            ::NewRelic::Agent.logger.error(error.message)
            disconnect
            shutdown
          end

          def generate_environment_report
            @environment_report = environment_for_connect
          end

          # Checks whether we should send environment info, and if so,
          # returns the snapshot from the local environment.
          # Generating the EnvironmentReport has the potential to trigger
          # require calls in Rails environments, so this method should only
          # be called synchronously from on the main thread.
          def environment_for_connect
            Agent.config[:send_environment_info] ? Array(EnvironmentReport.new) : []
          end

          # Initializes the hash of settings that we send to the
          # server. Returns a literal hash containing the options
          def connect_settings
            {
              :pid => $$,
              :host => @local_host,
              :app_name => Agent.config.app_names,
              :language => 'ruby',
              :agent_version => NewRelic::VERSION::STRING,
              :environment => @environment_report,
              :settings => Agent.config.to_collector_hash,
            }
          end

          # Returns connect data passed back from the server
          def connect_to_server
            @service.connect(connect_settings)
          end

          # apdex_f is always 4 times the apdex_t
          def apdex_f
            (4 * Agent.config[:apdex_t]).to_f
          end

          # Sets the collector host and connects to the server, then
          # invokes the final configuration with the returned data
          def query_server_for_configuration
            finish_setup(connect_to_server)
          end

          # Takes a hash of configuration data returned from the
          # server and uses it to set local variables and to
          # initialize various parts of the agent that are configured
          # separately.
          #
          # Can accommodate most arbitrary data - anything extra is
          # ignored unless we say to do something with it here.
          def finish_setup(config_data)
            return if config_data == nil

            @service.agent_id = config_data['agent_run_id'] if @service

            if config_data['agent_config']
              ::NewRelic::Agent.logger.debug "Using config from server"
            end

            ::NewRelic::Agent.logger.debug "Server provided config: #{config_data.inspect}"
            server_config = NewRelic::Agent::Configuration::ServerSource.new(config_data, Agent.config)
            Agent.config.apply_config(server_config, 1)
            log_connection!(config_data) if @service

            @transaction_rules = RulesEngine.from_specs(config_data['transaction_name_rules'])
            @stats_engine.metric_rules = RulesEngine.from_specs(config_data['metric_name_rules'])

            # If you're adding something else here to respond to the server-side config,
            # use Agent.instance.events.subscribe(:finished_configuring) callback instead!

            @beacon_configuration = BeaconConfiguration.new
          end

          # Logs when we connect to the server, for debugging purposes
          # - makes sure we know if an agent has not connected
          def log_connection!(config_data)
            ::NewRelic::Agent.logger.debug "Connected to NewRelic Service at #{@service.collector.name}"
            ::NewRelic::Agent.logger.debug "Agent Run       = #{@service.agent_id}."
            ::NewRelic::Agent.logger.debug "Connection data = #{config_data.inspect}"
            if config_data['messages'] && config_data['messages'].any?
              log_collector_messages(config_data['messages'])
            end
          end

          def log_collector_messages(messages)
            messages.each do |message|
              ::NewRelic::Agent.logger.send(message['level'].downcase, message['message'])
            end
          end
        end
        include Connect

        # Accepts an array of (metrics, transaction_traces, errors) and merges
        # it into our current collection of data to send. Can be
        # dangerous if we re-merge the same data more than once - it
        # will be sent multiple times.
        def merge_data_from(data)
          metrics, transaction_traces, errors = data
          @stats_engine.merge!(metrics) if metrics
          if transaction_traces && transaction_traces.respond_to?(:any?) &&
              transaction_traces.any?
            @transaction_sampler.merge!(transaction_traces)
          end
          if errors && errors.respond_to?(:each)
            @error_collector.merge!(errors)
          end
        end

        public :merge_data_from

        # Connect to the server and validate the license.  If successful,
        # connected? returns true when finished.  If not successful, you can
        # keep calling this.  Return false if we could not establish a
        # connection with the server and we should not retry, such as if
        # there's a bad license key.
        #
        # Set keep_retrying=false to disable retrying and return asap, such as when
        # invoked in the foreground.  Otherwise this runs until a successful
        # connection is made, or the server rejects us.
        #
        # * <tt>:keep_retrying => false</tt> to only try to connect once, and
        #   return with the connection set to nil.  This ensures we may try again
        #   later (default true).
        # * <tt>force_reconnect => true</tt> if you want to establish a new connection
        #   to the server before running the worker loop.  This means you get a separate
        #   agent run and New Relic sees it as a separate instance (default is false).
        def connect(options={})
          defaults = {
            :keep_retrying => Agent.config[:keep_retrying],
            :force_reconnect => Agent.config[:force_reconnect]
          }
          opts = defaults.merge(options)

          return unless should_connect?(opts[:force_reconnect])

          ::NewRelic::Agent.logger.debug "Connecting Process to New Relic: #$0"
          query_server_for_configuration
          @connected_pid = $$
          @connect_state = :connected
        rescue NewRelic::Agent::LicenseException => e
          handle_license_error(e)
        rescue NewRelic::Agent::UnrecoverableAgentException => e
          handle_unrecoverable_agent_error(e)
        rescue Timeout::Error, NewRelic::Agent::ServerConnectionException => e
          log_error(e)
          if opts[:keep_retrying]
            note_connect_failure
            ::NewRelic::Agent.logger.warn "Will re-attempt in #{connect_retry_period} seconds"
            sleep connect_retry_period
            retry
          else
            disconnect
          end
        rescue StandardError => e
          handle_other_error(e)
        end

        # Who am I? Well, this method can tell you your hostname.
        def determine_host
          Socket.gethostname
        end

        # Delegates to the control class to determine the root
        # directory of this project
        def determine_home_directory
          control.root
        end

        # calls the busy harvester and collects timeslice data to
        # send later
        def harvest_timeslice_data
          NewRelic::Agent::BusyCalculator.harvest_busy
          @stats_engine.harvest
        end

        def harvest_and_send_timeslice_data
          timeslices = harvest_timeslice_data
          begin
            @service.metric_data(timeslices)
          rescue UnrecoverableServerException => e
            ::NewRelic::Agent.logger.debug e.message
          rescue => e
            NewRelic::Agent.logger.info("Failed to send timeslice data, trying again later. Error:", e)
            @stats_engine.merge!(timeslices)
          end
        end

        def harvest_and_send_slowest_sql
          # FIXME add the code to try to resend if our connection is down
          sql_traces = @sql_sampler.harvest
          unless sql_traces.empty?
            ::NewRelic::Agent.logger.debug "Sending (#{sql_traces.size}) sql traces"
            begin
              @service.sql_trace_data(sql_traces)
            rescue UnrecoverableServerException => e
              ::NewRelic::Agent.logger.debug e.message
            rescue => e
              ::NewRelic::Agent.logger.debug "Remerging SQL traces after #{e.class.name}: #{e.message}"
              @sql_sampler.merge!(sql_traces)
            end
          end
        end

        # This handles getting the transaction traces and then sending
        # them across the wire.  This includes gathering SQL
        # explanations, stripping out stack traces, and normalizing
        # SQL.  note that we explain only the sql statements whose
        # segments' execution times exceed our threshold (to avoid
        # unnecessary overhead of running explains on fast queries.)
        def harvest_and_send_transaction_traces
          traces = @transaction_sampler.harvest
          unless traces.empty?
            begin
              send_transaction_traces(traces)
            rescue UnrecoverableServerException => e
              # This indicates that there was a problem with the POST body, so
              # we discard the traces rather than trying again later.
              ::NewRelic::Agent.logger.debug("Server rejected transaction traces, discarding. Error: ", e)
            rescue => e
              ::NewRelic::Agent.logger.error("Failed to send transaction traces, will re-attempt next harvest. Error: ", e)
              @transaction_sampler.merge!(traces)
            end
          end
        end

        def send_transaction_traces(traces)
          start_time = Time.now
          ::NewRelic::Agent.logger.debug "Sending (#{traces.length}) transaction traces"

          options = {}
          unless NewRelic::Agent::Database.record_sql_method == :off
            options[:record_sql] = NewRelic::Agent::Database.record_sql_method
          end

          if Agent.config[:'transaction_tracer.explain_enabled']
            options[:explain_sql] = Agent.config[:'transaction_tracer.explain_threshold']
          end

          traces.each { |trace| trace.prepare_to_send!(options) }

          @service.transaction_sample_data(traces)
          ::NewRelic::Agent.logger.debug "Sent slowest sample (#{@service.agent_id}) in #{Time.now - start_time} seconds"
        end

        def harvest_and_send_for_agent_commands(disconnecting=false)
          data = @agent_command_router.harvest_data_to_send(disconnecting)
          data.each do |service_method, payload|
            @service.send(service_method, payload)
          end
        end

        # Handles getting the errors from the error collector and
        # sending them to the server, and any error cases like trying
        # to send very large errors
        def harvest_and_send_errors
          errors = @error_collector.harvest_errors
          if errors && !errors.empty?
            ::NewRelic::Agent.logger.debug "Sending #{errors.length} errors"
            begin
              @service.error_data(errors)
            rescue UnrecoverableServerException => e
              ::NewRelic::Agent.logger.debug e.message
            rescue => e
              ::NewRelic::Agent.logger.debug "Failed to send error traces, will try again later. Error:", e
              @error_collector.merge!(errors)
            end
          end
        end

        # Fetch samples from the RequestSampler and send them.
        def harvest_and_send_analytic_event_data
          samples = @request_sampler.harvest
          begin
            @service.analytic_event_data(samples) unless samples.empty?
          rescue
            @request_sampler.merge!(samples)
            raise
          end
        end

        def check_for_and_handle_agent_commands
          @agent_command_router.check_for_and_handle_agent_commands
        end

        def transmit_data(disconnecting=false)
          harvest_lock.synchronize do
            transmit_data_already_locked(disconnecting)
          end
        end

        # This method is expected to only be called with the harvest_lock
        # already held
        def transmit_data_already_locked(disconnecting)
          now = Time.now
          ::NewRelic::Agent.logger.debug "Sending data to New Relic Service"

          @events.notify(:before_harvest)
          @service.session do # use http keep-alive
            harvest_and_send_errors
            harvest_and_send_transaction_traces
            harvest_and_send_slowest_sql
            harvest_and_send_timeslice_data
            harvest_and_send_analytic_event_data

            check_for_and_handle_agent_commands
            harvest_and_send_for_agent_commands(disconnecting)
          end
        rescue EOFError => e
          ::NewRelic::Agent.logger.warn("EOFError after #{Time.now - now}s when transmitting data to New Relic Service.")
          ::NewRelic::Agent.logger.debug(e)
        rescue => e
          retry_count ||= 0
          retry_count += 1
          if retry_count <= 1
            ::NewRelic::Agent.logger.debug "retrying transmit_data after #{e}"
            retry
          end
          raise e
        ensure
          NewRelic::Agent::Database.close_connections
          duration = (Time.now - now).to_f
          @stats_engine.record_metrics('Supportability/Harvest', duration)
        end

        private :transmit_data_already_locked

        # This method contacts the server to send remaining data and
        # let the server know that the agent is shutting down - this
        # allows us to do things like accurately set the end of the
        # lifetime of the process
        #
        # If this process comes from a parent process, it will not
        # disconnect, so that the parent process can continue to send data
        def graceful_disconnect
          if connected?
            begin
              @service.request_timeout = 10
              transmit_data(true)

              if @connected_pid == $$ && !@service.kind_of?(NewRelic::Agent::NewRelicService)
                ::NewRelic::Agent.logger.debug "Sending New Relic service agent run shutdown message"
                @service.shutdown(Time.now.to_f)
              else
                ::NewRelic::Agent.logger.debug "This agent connected from parent process #{@connected_pid}--not sending shutdown"
              end
              ::NewRelic::Agent.logger.debug "Graceful disconnect complete"
            rescue Timeout::Error, StandardError => e
              ::NewRelic::Agent.logger.debug "Error when disconnecting #{e.class.name}: #{e.message}"
            end
          else
            ::NewRelic::Agent.logger.debug "Bypassing graceful disconnect - agent not connected"
          end
        end
      end

      extend ClassMethods
      include InstanceMethods
      include BrowserMonitoring
    end
  end
end
