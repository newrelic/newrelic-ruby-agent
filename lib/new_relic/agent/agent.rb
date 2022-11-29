# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'socket'
require 'net/https'
require 'net/http'
require 'logger'
require 'zlib'
require 'stringio'
require 'new_relic/constants'
require 'new_relic/traced_thread'
require 'new_relic/coerce'
require 'new_relic/agent/autostart'
require 'new_relic/agent/harvester'
require 'new_relic/agent/hostname'
require 'new_relic/agent/new_relic_service'
require 'new_relic/agent/pipe_service'
require 'new_relic/agent/configuration/manager'
require 'new_relic/agent/database'
require 'new_relic/agent/instrumentation/resque/helper'
require 'new_relic/agent/commands/agent_command_router'
require 'new_relic/agent/event_listener'
require 'new_relic/agent/distributed_tracing'
require 'new_relic/agent/monitors'
require 'new_relic/agent/transaction_event_recorder'
require 'new_relic/agent/custom_event_aggregator'
require 'new_relic/agent/span_event_aggregator'
require 'new_relic/agent/log_event_aggregator'
require 'new_relic/agent/sampler_collection'
require 'new_relic/agent/javascript_instrumentor'
require 'new_relic/agent/vm/monotonic_gc_profiler'
require 'new_relic/agent/utilization_data'
require 'new_relic/environment_report'
require 'new_relic/agent/attribute_filter'
require 'new_relic/agent/adaptive_sampler'
require 'new_relic/agent/connect/request_builder'
require 'new_relic/agent/connect/response_handler'

require 'new_relic/agent/agent/connect'
require 'new_relic/agent/agent/harvest'
require 'new_relic/agent/agent/start_worker_thread'
require 'new_relic/agent/agent/startup'
require 'new_relic/agent/agent/special_startup'
require 'new_relic/agent/agent/shutdown'
require 'new_relic/agent/agent/transmit'

module NewRelic
  module Agent
    # The Agent is a singleton that is instantiated when the plugin is
    # activated.  It collects performance data from ruby applications
    # in realtime as the application runs, and periodically sends that
    # data to the NewRelic server.
    class Agent
      def self.config
        ::NewRelic::Agent.config
      end

      include Connect
      include Harvest
      include StartWorkerThread
      include SpecialStartup
      include Startup
      include Shutdown
      include Transmit

      def initialize
        init_basics
        init_components
        init_event_handlers
        setup_attribute_filter
      end

      private

      def init_basics
        @started = false
        @event_loop = nil
        @worker_thread = nil
        @connect_state = :pending
        @connect_attempts = 0
        @waited_on_connect = nil
        @connected_pid = nil
        @wait_on_connect_mutex = Mutex.new
        @after_fork_lock = Mutex.new
        @wait_on_connect_condition = ConditionVariable.new
      end

      def init_components
        @service = NewRelicService.new
        @events = EventListener.new
        @stats_engine = StatsEngine.new
        @transaction_sampler = TransactionSampler.new
        @sql_sampler = SqlSampler.new
        @transaction_rules = RulesEngine.new
        @monotonic_gc_profiler = VM::MonotonicGCProfiler.new
        @adaptive_sampler = AdaptiveSampler.new(Agent.config[:sampling_target],
          Agent.config[:sampling_target_period_in_seconds])
      end

      def init_event_handlers
        @agent_command_router = Commands::AgentCommandRouter.new(@events)
        @monitors = Monitors.new(@events)
        @error_collector = ErrorCollector.new(@events)
        @harvest_samplers = SamplerCollection.new(@events)
        @javascript_instrumentor = JavaScriptInstrumentor.new(@events)
        @harvester = Harvester.new(@events)
        @transaction_event_recorder = TransactionEventRecorder.new(@events)
        @custom_event_aggregator = CustomEventAggregator.new(@events)
        @span_event_aggregator = SpanEventAggregator.new(@events)
        @log_event_aggregator = LogEventAggregator.new(@events)
      end

      def setup_attribute_filter
        refresh_attribute_filter

        @events.subscribe(:initial_configuration_complete) do
          refresh_attribute_filter
        end
      end

      public

      def refresh_attribute_filter
        @attribute_filter = AttributeFilter.new(Agent.config)
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
        # builder for JS agent scripts to inject
        attr_reader :javascript_instrumentor
        # cross application tracing ids and encoding
        attr_reader :cross_process_id
        attr_reader :cross_app_encoding_bytes
        # service for communicating with collector
        attr_accessor :service
        # Global events dispatcher. This will provides our primary mechanism
        # for agent-wide events, such as finishing configuration, error notification
        # and request before/after from Rack.
        attr_reader :events

        # listens and responds to events that need to process headers
        # for synthetics and distributed tracing
        attr_reader :monitors
        # Transaction and metric renaming rules as provided by the
        # collector on connect.  The former are applied during txns,
        # the latter during harvest.
        attr_accessor :transaction_rules
        # Responsible for restarting the harvest thread
        attr_reader :harvester
        # GC::Profiler.total_time is not monotonic so we wrap it.
        attr_reader :monotonic_gc_profiler
        attr_reader :custom_event_aggregator
        attr_reader :span_event_aggregator
        attr_reader :log_event_aggregator
        attr_reader :transaction_event_recorder
        attr_reader :attribute_filter
        attr_reader :adaptive_sampler
        attr_reader :environment_report

        def transaction_event_aggregator
          @transaction_event_recorder.transaction_event_aggregator
        end

        def synthetics_event_aggregator
          @transaction_event_recorder.synthetics_event_aggregator
        end

        def agent_id=(agent_id)
          @service.agent_id = agent_id
        end

        # This method should be called in a forked process after a fork.
        # It assumes the parent process initialized the agent, but does
        # not assume the agent started.
        #
        # The call is idempotent, but not reentrant.
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
        def after_fork(options = {})
          return unless needs_after_fork_work?

          ::NewRelic::Agent.logger.debug("Starting the worker thread in #{Process.pid} (parent #{Process.ppid}) after forking.")

          channel_id = options[:report_to_channel]
          install_pipe_service(channel_id) if channel_id

          # Clear out locks and stats left over from parent process
          reset_objects_with_locks
          drop_buffered_data

          setup_and_start_agent(options)
        end

        def needs_after_fork_work?
          needs_restart = false
          @after_fork_lock.synchronize do
            needs_restart = @harvester.needs_restart?
            @harvester.mark_started
          end

          return false if !needs_restart ||
            !Agent.config[:agent_enabled] ||
            !Agent.config[:monitor_mode] ||
            disconnected? ||
            !control.security_settings_valid?

          true
        end

        def install_pipe_service(channel_id)
          @service = PipeService.new(channel_id)
          if connected?
            @connected_pid = Process.pid
          else
            ::NewRelic::Agent.logger.debug("Child process #{Process.pid} not reporting to non-connected parent (process #{Process.ppid}).")
            @service.shutdown
            disconnect
          end
        end

        def revert_to_default_configuration
          Agent.config.remove_config_type(:manual)
          Agent.config.remove_config_type(:server)
        end

        def trap_signals_for_litespeed
          # if litespeed, then ignore all future SIGUSR1 - it's
          # litespeed trying to shut us down
          if Agent.config[:dispatcher] == :litespeed
            Signal.trap("SIGUSR1", "IGNORE")
            Signal.trap("SIGTERM", "IGNORE")
          end
        end

        # Sets a thread local variable as to whether we should or
        # should not record sql in the current thread. Returns the
        # previous value, if there is one
        def set_record_sql(should_record) # THREAD_LOCAL_ACCESS
          state = Tracer.state
          prev = state.record_sql
          state.record_sql = should_record
          prev.nil? || prev
        end

        # Push flag indicating whether we should be tracing in this
        # thread. This uses a stack which allows us to disable tracing
        # children of a transaction without affecting the tracing of
        # the whole transaction
        def push_trace_execution_flag(should_trace = false) # THREAD_LOCAL_ACCESS
          Tracer.state.push_traced(should_trace)
        end

        # Pop the current trace execution status.  Restore trace execution status
        # to what it was before we pushed the current flag.
        def pop_trace_execution_flag # THREAD_LOCAL_ACCESS
          Tracer.state.pop_traced
        end

        # Clear out the metric data, errors, and transaction traces, etc.
        def drop_buffered_data
          @stats_engine.reset!
          @error_collector.drop_buffered_data
          @transaction_sampler.reset!
          @transaction_event_recorder.drop_buffered_data
          @custom_event_aggregator.reset!
          @span_event_aggregator.reset!
          @log_event_aggregator.reset!
          @sql_sampler.reset!

          if Agent.config[:clear_transaction_state_after_fork]
            Tracer.clear_state
          end
        end

        # Clear out state for any objects that we know lock from our parents
        # This is necessary for cases where we're in a forked child and Ruby
        # might be holding locks for background thread that aren't there anymore.
        def reset_objects_with_locks
          @stats_engine = StatsEngine.new
        end

        def flush_pipe_data
          if connected? && @service.is_a?(PipeService)
            transmit_data_types
          end
        end

        private

        # A shorthand for NewRelic::Control.instance
        def control
          NewRelic::Control.instance
        end

        def container_for_endpoint(endpoint)
          case endpoint
          when :metric_data then @stats_engine
          when :transaction_sample_data then @transaction_sampler
          when :error_data then @error_collector.error_trace_aggregator
          when :error_event_data then @error_collector.error_event_aggregator
          when :analytic_event_data then transaction_event_aggregator
          when :custom_event_data then @custom_event_aggregator
          when :span_event_data then span_event_aggregator
          when :sql_trace_data then @sql_sampler
          when :log_event_data then @log_event_aggregator
          end
        end

        def merge_data_for_endpoint(endpoint, data)
          if data && !data.empty?
            container = container_for_endpoint(endpoint)
            if container.respond_to?(:has_metadata?) && container.has_metadata?
              container_for_endpoint(endpoint).merge!(data, false)
            else
              container_for_endpoint(endpoint).merge!(data)
            end
          end
        rescue => e
          NewRelic::Agent.logger.error("Error while merging #{endpoint} data from child: ", e)
        end

        public :merge_data_for_endpoint

        # Establish a connection to New Relic servers.
        #
        # By default, if a connection has already been established, this method
        # will be a no-op.
        #
        # @param [Hash] options
        # @option options [Boolean] :keep_retrying (true)
        #   If true, this method will block until a connection is successfully
        #   established, continuing to retry upon failure. If false, this method
        #   will return after either successfully connecting, or after failing
        #   once.
        #
        # @option options [Boolean] :force_reconnect (false)
        #   If true, this method will force establishment of a new connection
        #   with New Relic, even if there is already an existing connection.
        #   This is useful primarily when re-establishing a new connection after
        #   forking off from a parent process.
        #
        def connect(options = {})
          opts = connect_options(options)
          return unless should_connect?(opts[:force_reconnect])

          ::NewRelic::Agent.logger.debug("Connecting Process to New Relic: #$0")
          connect_to_server
          @connected_pid = $$
          @connect_state = :connected
          signal_connected
        rescue NewRelic::Agent::ForceDisconnectException => e
          handle_force_disconnect(e)
        rescue NewRelic::Agent::LicenseException => e
          handle_license_error(e)
        rescue NewRelic::Agent::UnrecoverableAgentException => e
          handle_unrecoverable_agent_error(e)
        rescue StandardError, Timeout::Error, NewRelic::Agent::ServerConnectionException => e
          retry if retry_from_error?(e, opts)
        rescue Exception => e
          ::NewRelic::Agent.logger.error("Exception of unexpected type during Agent#connect():", e)

          raise
        end

        def connect_options(options)
          {
            keep_retrying: Agent.config[:keep_retrying],
            force_reconnect: Agent.config[:force_reconnect]
          }.merge(options)
        end

        def retry_from_error?(e, opts)
          # Allow a killed (aborting) thread to continue exiting during shutdown.
          # See: https://github.com/newrelic/newrelic-ruby-agent/issues/340
          raise if Thread.current.status == 'aborting'

          log_error(e)
          return false unless opts[:keep_retrying]

          note_connect_failure
          ::NewRelic::Agent.logger.info("Will re-attempt in #{connect_retry_period} seconds")
          sleep(connect_retry_period)
          true
        end

        # Delegates to the control class to determine the root
        # directory of this project
        def determine_home_directory
          control.root
        end

        def send_data_to_endpoint(endpoint, payload, container)
          begin
            @service.send(endpoint, payload)
          rescue ForceRestartException, ForceDisconnectException
            raise
          rescue SerializationError => e
            NewRelic::Agent.logger.warn("Failed to serialize data for #{endpoint}, discarding. Error: ", e)
          rescue UnrecoverableServerException => e
            NewRelic::Agent.logger.warn("#{endpoint} data was rejected by remote service, discarding. Error: ", e)
          rescue ServerConnectionException => e
            log_remote_unavailable(endpoint, e)
            container.merge!(payload)
          rescue => e
            NewRelic::Agent.logger.info("Unable to send #{endpoint} data, will try again later. Error: ", e)
            container.merge!(payload)
          end
        end

        def check_for_and_handle_agent_commands
          begin
            @agent_command_router.check_for_and_handle_agent_commands
          rescue ForceRestartException, ForceDisconnectException
            raise
          rescue UnrecoverableServerException => e
            NewRelic::Agent.logger.warn("get_agent_commands message was rejected by remote service, discarding. Error: ", e)
          rescue ServerConnectionException => e
            log_remote_unavailable(:get_agent_commands, e)
          rescue => e
            NewRelic::Agent.logger.info("Error during check_for_and_handle_agent_commands, will retry later: ", e)
          end
        end

        def log_remote_unavailable(endpoint, e)
          NewRelic::Agent.logger.debug("Unable to send #{endpoint} data, will try again later. Error: ", e)
          NewRelic::Agent.record_metric("Supportability/remote_unavailable", 0.0)
          NewRelic::Agent.record_metric("Supportability/remote_unavailable/#{endpoint.to_s}", 0.0)
        end
      end

      extend ClassMethods
      include InstanceMethods
    end
  end
end
