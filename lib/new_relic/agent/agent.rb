require 'socket'
require 'net/https'
require 'net/http'
require 'logger'
require 'zlib'
require 'stringio'
require 'new_relic/agent/new_relic_service'
require 'new_relic/agent/pipe_service'
require 'new_relic/agent/configuration/manager'
require 'new_relic/agent/database'
require 'new_relic/agent/thread_profiler'

module NewRelic
  module Agent

    # The Agent is a singleton that is instantiated when the plugin is
    # activated.  It collects performance data from ruby applications
    # in realtime as the application runs, and periodically sends that
    # data to the NewRelic server.
    class Agent
      extend NewRelic::Agent::Configuration::Instance

      def initialize
        @launch_time = Time.now

        @metric_ids = {}
        @stats_engine = NewRelic::Agent::StatsEngine.new
        @transaction_sampler = NewRelic::Agent::TransactionSampler.new
        @sql_sampler = NewRelic::Agent::SqlSampler.new
        @thread_profiler = NewRelic::Agent::ThreadProfiler.new
        @error_collector = NewRelic::Agent::ErrorCollector.new
        @connect_attempts = 0

        @last_harvest_time = Time.now
        @obfuscator = lambda {|sql| NewRelic::Agent::Database.default_sql_obfuscator(sql) }
        @forked = false

        # FIXME: temporary work around for RUBY-839
        if Agent.config[:monitor_mode]
          @service = NewRelic::Agent::NewRelicService.new
        end

        txn_tracer_enabler = Proc.new do
          if NewRelic::Agent.config[:'transaction_tracer.enabled'] ||
              NewRelic::Agent.config[:developer_mode]
            @stats_engine.transaction_sampler = @transaction_sampler
          else
            @stats_engine.transaction_sampler = nil
          end
        end
        Agent.config.register_callback(:'transaction_tracer.enabled', &txn_tracer_enabler)
        Agent.config.register_callback(:developer_mode, &txn_tracer_enabler)
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
        # begins a thread profile session when instructed by agent commands
        attr_reader :thread_profiler
        # error collector is a simple collection of recorded errors
        attr_reader :error_collector
        # whether we should record raw, obfuscated, or no sql
        attr_reader :record_sql
        # a cached set of metric_ids to save the collector some time -
        # it returns a metric id for every metric name we send it, and
        # in the future we transmit using the metric id only
        attr_reader :metric_ids
        # in theory a set of rules applied by the agent to the output
        # of its metrics. Currently unimplemented
        attr_reader :url_rules
        # a configuration for the Real User Monitoring system -
        # handles things like static setup of the header for inclusion
        # into pages
        attr_reader :beacon_configuration
        # cross process id's and encoding
        attr_reader :cross_process_id
        attr_reader :cross_process_encoding_bytes
        # service for communicating with collector
        attr_accessor :service


        # Returns the length of the unsent errors array, if it exists,
        # otherwise nil
        def unsent_errors_size
          @unsent_errors.length if @unsent_errors
        end

        # Returns the length of the traces array, if it exists,
        # otherwise nil
        def unsent_traces_size
          @traces.length if @traces
        end

        # Initializes the unsent timeslice data hash, if needed, and
        # returns the number of keys it contains
        def unsent_timeslice_data
          @unsent_timeslice_data ||= {}
          @unsent_timeslice_data.keys.length
        end

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
            NewRelic::Agent::Instrumentation::MetricFrame.record_apdex(metric_info, duration_seconds, duration_seconds, is_error)
          end
          metrics = metric_info.summary_metrics

          metrics << metric
          metrics.each do |name|
            stats = stats_engine.get_stats_no_scope(name)
            stats.record_data_point(duration_seconds)
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
          @forked = true
          Agent.config.apply_config(NewRelic::Agent::Configuration::ManualSource.new(options), 1)

          # @connected gets false after we fail to connect or have an error
          # connecting.  @connected has nil if we haven't finished trying to connect.
          # or we didn't attempt a connection because this is the master process

          if channel_id = options[:report_to_channel]
            @service = NewRelic::Agent::PipeService.new(channel_id)
            @connected_pid = $$
            @metric_ids = {}
          end

          return if !Agent.config[:agent_enabled] ||
            !Agent.config[:monitor_mode] ||
            @connected == false ||
            @worker_thread && @worker_thread.alive?

          ::NewRelic::Agent.logger.debug "Starting the worker thread in #{$$} after forking."

          # Clear out stats that are left over from parent process
          reset_stats

          # Don't ever check to see if this is a spawner.  If we're in a forked process
          # I'm pretty sure we're not also forking new instances.
          start_worker_thread(options)
          @stats_engine.start_sampler_thread
        end

        def forked?
          @forked
        end

        # True if we have initialized and completed 'start'
        def started?
          @started
        end

        # Return nil if not yet connected, true if successfully started
        # and false if we failed to start.
        def connected?
          @connected
        end

        # Attempt a graceful shutdown of the agent, running the worker
        # loop if it exists and is running.
        #
        # Options:
        # :force_send => (true/false) # force the agent to send data
        # before shutting down
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
          prev = Thread::current[:record_sql]
          Thread::current[:record_sql] = should_record
          prev.nil? || prev
        end

        # Sets a thread local variable as to whether we should or
        # should not record transaction traces in the current
        # thread. Returns the previous value, if there is one
        def set_record_tt(should_record)
          prev = Thread::current[:record_tt]
          Thread::current[:record_tt] = should_record
          prev.nil? || prev
        end

        # Push flag indicating whether we should be tracing in this
        # thread. This uses a stack which allows us to disable tracing
        # children of a transaction without affecting the tracing of
        # the whole transaction
        def push_trace_execution_flag(should_trace=false)
          value = Thread.current[:newrelic_untraced]
          if (value.nil?)
            Thread.current[:newrelic_untraced] = []
          end

          Thread.current[:newrelic_untraced] << should_trace
        end

        # Pop the current trace execution status.  Restore trace execution status
        # to what it was before we pushed the current flag.
        def pop_trace_execution_flag
          Thread.current[:newrelic_untraced].pop if Thread.current[:newrelic_untraced]
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
            log_app_names
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
            return if log_if(dispatcher_name.empty?, :warn, "No dispatcher detected.")
            ::NewRelic::Agent.logger.info "Dispatcher: #{dispatcher_name}"
          end

          # Logs the configured application names
          def log_app_names
            names = Agent.config.app_names
            if names.respond_to?(:any?) && names.any?
              ::NewRelic::Agent.logger.info "Application: #{names.join(", ")}"
            else
              ::NewRelic::Agent.logger.error 'Unable to determine application name. Please set the application name in your newrelic.yml or in a NEW_RELIC_APP_NAME environment variable.'
            end
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

          # A helper method that logs a condition if that condition is
          # true. Mentally cleaner than having every method set a
          # local and log if it is true
          def log_if(boolean, level, message)
            ::NewRelic::Agent.logger.send(level, message) if boolean
            boolean
          end

          # A helper method that logs a condition unless that
          # condition is true. Mentally cleaner than having every
          # method set a local and log unless it is true
          def log_unless(boolean, level, message)
            ::NewRelic::Agent.logger.send(level, message) unless boolean
            boolean
          end

          # Warn the user if they have configured their agent not to
          # send data, that way we can see this clearly in the log file
          def monitoring?
            log_unless(Agent.config[:monitor_mode], :warn,
                       "Agent configured not to send data in this environment.")
          end

          # Tell the user when the license key is missing so they can
          # fix it by adding it to the file
          def has_license_key?
            log_unless(Agent.config[:license_key], :warn,
                       "No license key found in newrelic.yml config. " +
                       "This often means your newrelic.yml is missing a section for the running environment '#{NewRelic::Control.instance.env}'")
          end

          # A correct license key exists and is of the proper length
          def has_correct_license_key?
            has_license_key? && correct_license_length
          end

          # A license key is an arbitrary 40 character string,
          # usually looks something like a SHA1 hash
          def correct_license_length
            key = Agent.config[:license_key]
            log_unless((key.length == 40), :error, "Invalid license key: #{key}")
          end

          # If we're using a dispatcher that forks before serving
          # requests, we need to wait until the children are forked
          # before connecting, otherwise the parent process sends odd data
          def using_forking_dispatcher?
            log_if([:passenger, :unicorn].include?(Agent.config[:dispatcher]),
                   :info, "Connecting workers after forking.")
          end

          # Sanity-check the agent configuration and start the agent,
          # setting up the worker thread and the exit handler to shut
          # down the agent
          def check_config_and_start_agent
            return unless monitoring? && has_correct_license_key?
            return if using_forking_dispatcher?
            connect_in_foreground if Agent.config[:sync_startup]
            start_worker_thread
            install_exit_handler
          end
        end

        include Start

        # Logs a bunch of data and starts the agent, if needed
        def start
          return if already_started? || disabled?
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
          @unsent_errors = []
          @traces = nil
          @unsent_timeslice_data = {}
          @last_harvest_time = Time.now
          @launch_time = Time.now
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
            @metric_ids = {}
            @connected = nil
            sleep 30
          end

          # when a disconnect is requested, stop the current thread, which
          # is the worker thread that gathers data and talks to the
          # server.
          def handle_force_disconnect(error)
            ::NewRelic::Agent.logger.warn "New Relic forced this agent to disconnect (#{error.message})"
            disconnect
          end

          # there is a problem with connecting to the server, so we
          # stop trying to connect and shut down the agent
          def handle_server_connection_problem(error)
            ::NewRelic::Agent.logger.error "Unable to establish connection with the server.", error
            disconnect
          end

          # Handles an unknown error in the worker thread by logging
          # it and disconnecting the agent, since we are now in an
          # unknown state
          def handle_other_error(error)
            ::NewRelic::Agent.logger.error "Terminating worker loop.", error
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
          rescue NewRelic::Agent::ServerConnectionException => e
            handle_server_connection_problem(e)
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
                if @connected
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
          ::NewRelic::Agent.logger.debug "Creating Ruby Agent worker thread."
          @worker_thread = NewRelic::Agent::AgentThread.new('Worker Loop') do
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
          # the frequency with which we should try to connect to the
          # server at the moment.
          attr_accessor :connect_retry_period
          # number of attempts we've made to contact the server
          attr_accessor :connect_attempts

          # Disconnect just sets connected to false, which prevents
          # the agent from trying to connect again
          def disconnect
            @connected = false
            true
          end

          # We've tried to connect if @connected is not nil, or if we
          # are forcing reconnection (i.e. in the case of an
          # after_fork with long running processes)
          def tried_to_connect?(options)
            !(@connected.nil? || options[:force_reconnect])
          end

          # We keep trying by default, but you can disable it with the
          # :keep_retrying option set to false
          def should_keep_retrying?(options)
            @keep_retrying = (options[:keep_retrying].nil? || options[:keep_retrying])
          end

          # Retry period is a minute for each failed attempt that
          # we've made. This should probably do some sort of sane TCP
          # backoff to prevent hammering the server, but a minute for
          # each attempt seems to work reasonably well.
          def get_retry_period
            return 600 if self.connect_attempts > 6
            connect_attempts * 60
          end

          def increment_retry_period! #:nodoc:
            self.connect_retry_period=(get_retry_period)
          end

          # We should only retry when there has not been a more
          # serious condition that would prevent it. We increment the
          # connect attempts and the retry period, to prevent constant
          # connection attempts, and tell the user what we're doing by
          # logging.
          def should_retry?
            if @keep_retrying
              self.connect_attempts=(connect_attempts + 1)
              increment_retry_period!
              ::NewRelic::Agent.logger.warn "Will re-attempt in #{connect_retry_period} seconds"
              true
            else
              disconnect
              false
            end
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

          # Checks whether we should send environment info, and if so,
          # returns the snapshot from the local environment
          def environment_for_connect
            Agent.config[:send_environment_info] ? Control.instance.local_env.snapshot : []
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
              :environment => environment_for_connect,
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
            server_config = NewRelic::Agent::Configuration::ServerSource.new(config_data)
            Agent.config.apply_config(server_config, 1)
            log_connection!(config_data) if @service

            @cross_process_id = Agent.config[:cross_process_id]
            @cross_process_encoding_key = Agent.config[:encoding_key]
            @cross_process_encoding_bytes = get_bytes(@cross_process_encoding_key) unless @cross_process_encoding_key.nil?

            @beacon_configuration = BeaconConfiguration.new
          end

          # Ruby 1.8.6 doesn't support the bytes method on strings.
          def get_bytes(value)
            return [] if value.nil?

            bytes = []
            value.each_byte do |b|
              bytes << b
            end
            bytes
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


        # Serialize all the important data that the agent might want
        # to send to the server. We could be sending this to file (
        # common in short-running background transactions ) or
        # alternately we could serialize via a pipe or socket to a
        # local aggregation device
        def serialize
          accumulator = []
          accumulator[1] = harvest_transaction_traces if @transaction_sampler
          accumulator[2] = harvest_errors if @error_collector
          accumulator[0] = harvest_timeslice_data
          reset_stats
          @metric_ids = {}
          accumulator
        end
        public :serialize

        # Accepts data as provided by the serialize method and merges
        # it into our current collection of data to send. Can be
        # dangerous if we re-merge the same data more than once - it
        # will be sent multiple times.
        def merge_data_from(data)
          metrics, transaction_traces, errors = data
          @stats_engine.merge_data(metrics) if metrics
          if transaction_traces && transaction_traces.respond_to?(:any?) &&
              transaction_traces.any?
            if @traces
              @traces += transaction_traces
            else
              @traces = transaction_traces
            end
          end
          if errors && errors.respond_to?(:any?) && errors.any?
            if @unsent_errors
              @unsent_errors = @unsent_errors + errors
            else
              @unsent_errors = errors
            end
          end
        end

        public :merge_data_from

        # Connect to the server and validate the license.  If successful,
        # @connected has true when finished.  If not successful, you can
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
        def connect(options)
          # Don't proceed if we already connected (@connected=true) or if we tried
          # to connect and were rejected with prejudice because of a license issue
          # (@connected=false), unless we're forced to by force_reconnect.
          return if tried_to_connect?(options)

          # wait a few seconds for the web server to boot, necessary in development
          @connect_retry_period = should_keep_retrying?(options) ? 10 : 0

          sleep connect_retry_period
          ::NewRelic::Agent.logger.debug "Connecting Process to New Relic: #$0"
          query_server_for_configuration
          @connected_pid = $$
          @connected = true
        rescue NewRelic::Agent::LicenseException => e
          handle_license_error(e)
        rescue Timeout::Error, StandardError => e
          log_error(e)
          if should_retry?
            retry
          else
            disconnect
          end
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

        # Checks whether this process is a Passenger or Unicorn
        # spawning server - if so, we probably don't intend to report
        # statistics from this process
        def is_application_spawner?
          $0 =~ /ApplicationSpawner|^unicorn\S* master/
        end

        # calls the busy harvester and collects timeslice data to
        # send later
        def harvest_timeslice_data(time=Time.now)
          # this creates timeslices that are harvested below
          NewRelic::Agent::BusyCalculator.harvest_busy

          @unsent_timeslice_data ||= {}
          @unsent_timeslice_data = @stats_engine.harvest_timeslice_data(@unsent_timeslice_data, @metric_ids)
          @unsent_timeslice_data
        end

        # takes an array of arrays of spec and id, adds it into the
        # metric cache so we can save the collector some work by
        # sending integers instead of strings
        def fill_metric_id_cache(pairs_of_specs_and_ids)
          Array(pairs_of_specs_and_ids).each do |metric_spec_hash, metric_id|
            metric_spec = MetricSpec.new(metric_spec_hash['name'],
                                         metric_spec_hash['scope'])
            @metric_ids[metric_spec] = metric_id
          end
        end

        # note - exceptions are logged in invoke_remote.  If an exception is encountered here,
        # then the metric data is downsampled for another
        # transmission later
        def harvest_and_send_timeslice_data
          now = Time.now
          NewRelic::Agent.instance.stats_engine.get_stats_no_scope('Supportability/invoke_remote').record_data_point(0.0)
          NewRelic::Agent.instance.stats_engine.get_stats_no_scope('Supportability/invoke_remote/metric_data').record_data_point(0.0)
          harvest_timeslice_data(now)
          # In this version of the protocol
          # we get back an assoc array of spec to id.
          metric_specs_and_ids = []
          begin
            metric_specs_and_ids = @service.metric_data(@last_harvest_time.to_f,
                                                now.to_f,
                                                @unsent_timeslice_data.values)
          rescue UnrecoverableServerException => e
            ::NewRelic::Agent.logger.debug e.message
          end
          fill_metric_id_cache(metric_specs_and_ids)

          ::NewRelic::Agent.logger.debug "#{now}: sent #{@unsent_timeslice_data.length} timeslices (#{@service.agent_id}) in #{Time.now - now} seconds"

          # if we successfully invoked this web service, then clear the unsent message cache.
          @unsent_timeslice_data = {}
          @last_harvest_time = now
        end

        # Fills the traces array with the harvested transactions from
        # the transaction sampler, subject to the setting for slowest
        # transaction threshold
        def harvest_transaction_traces
          @traces = @transaction_sampler.harvest(@traces)
          @traces
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
              @sql_sampler.merge sql_traces
            end
          end
        end

        # This handles getting the transaction traces and then sending
        # them across the wire.  This includes gathering SQL
        # explanations, stripping out stack traces, and normalizing
        # SQL.  note that we explain only the sql statements whose
        # segments' execution times exceed our threshold (to avoid
        # unnecessary overhead of running explains on fast queries.)
        def harvest_and_send_slowest_sample
          harvest_transaction_traces
          unless @traces.empty?
            now = Time.now
            ::NewRelic::Agent.logger.debug "Sending (#{@traces.length}) transaction traces"

            begin
              options = { :keep_backtraces => true }
              if !(NewRelic::Agent::Database.record_sql_method == :off)
                options[:record_sql] = NewRelic::Agent::Database.record_sql_method
              end
              if Agent.config[:'transaction_tracer.explain_enabled']
                options[:explain_sql] = Agent.config[:'transaction_tracer.explain_threshold']
              end
              traces = @traces.map {|trace| trace.prepare_to_send(options) }
              @service.transaction_sample_data(traces)
              ::NewRelic::Agent.logger.debug "Sent slowest sample (#{@service.agent_id}) in #{Time.now - now} seconds"
            rescue UnrecoverableServerException => e
              ::NewRelic::Agent.logger.debug e.message
            end
          end

          # if we succeed sending this sample, then we don't need to keep
          # the slowest sample around - it has been sent already and we
          # can clear the collection and move on
          @traces = nil
        end

        def harvest_and_send_thread_profile(disconnecting=false)
          @thread_profiler.stop(true) if disconnecting

          if @thread_profiler.finished?
            profile = @thread_profiler.harvest

            ::NewRelic::Agent.logger.debug "Sending thread profile #{profile.profile_id}"
            @service.profile_data(profile)
          end
        end

        # Gets the collection of unsent errors from the error
        # collector. We pass back in an existing array of errors that
        # may be left over from a previous send
        def harvest_errors
          @unsent_errors = @error_collector.harvest_errors(@unsent_errors)
          @unsent_errors
        end

        # Handles getting the errors from the error collector and
        # sending them to the server, and any error cases like trying
        # to send very large errors - we drop the oldest error on the
        # floor and try again
        def harvest_and_send_errors
          harvest_errors
          if @unsent_errors && @unsent_errors.length > 0
            ::NewRelic::Agent.logger.debug "Sending #{@unsent_errors.length} errors"
            begin
              @service.error_data(@unsent_errors)
            rescue UnrecoverableServerException => e
              ::NewRelic::Agent.logger.debug e.message
            end
            # if the remote invocation fails, then we never clear
            # @unsent_errors, and therefore we can re-attempt to send on
            # the next heartbeat.  Note the error collector maxes out at
            # 20 instances to prevent leakage
            @unsent_errors = []
          end
        end

        def check_for_agent_commands
          commands = @service.get_agent_commands
          ::NewRelic::Agent.logger.debug "Received get_agent_commands = #{commands.inspect}"

          @thread_profiler.respond_to_commands(commands) do |command_id, error|
            @service.agent_command_results(command_id, error)
          end
        end

        def transmit_data(disconnecting=false)
          now = Time.now
          ::NewRelic::Agent.logger.debug "Sending data to New Relic Service"
          harvest_and_send_errors
          harvest_and_send_slowest_sample
          harvest_and_send_slowest_sql
          harvest_and_send_timeslice_data
          harvest_and_send_thread_profile(disconnecting)

          check_for_agent_commands
        rescue => e
          retry_count ||= 0
          retry_count += 1
          if retry_count <= 1
            ::NewRelic::Agent.logger.debug "retrying transmit_data after #{e}"
            retry
          end
          raise e
        ensure
          NewRelic::Agent::Database.close_connections unless forked?
          @stats_engine.get_stats_no_scope('Supportability/Harvest') \
            .record_data_point((Time.now - now).to_f)
        end

        # This method contacts the server to send remaining data and
        # let the server know that the agent is shutting down - this
        # allows us to do things like accurately set the end of the
        # lifetime of the process
        #
        # If this process comes from a parent process, it will not
        # disconnect, so that the parent process can continue to send data
        def graceful_disconnect
          if @connected
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
