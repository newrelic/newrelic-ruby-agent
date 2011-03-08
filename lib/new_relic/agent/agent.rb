require 'socket'
require 'net/https'
require 'net/http'
require 'logger'
require 'zlib'
require 'stringio'

module NewRelic
  module Agent

    # The Agent is a singleton that is instantiated when the plugin is
    # activated.  It collects performance data from ruby applications
    # in realtime as the application runs, and periodically sends that
    # data to the NewRelic server.
    class Agent

      # Specifies the version of the agent's communication protocol with
      # the NewRelic hosted site.

      PROTOCOL_VERSION = 8
      # 14105: v8 (tag 2.10.3)
      # (no v7)
      # 10379: v6 (not tagged)
      # 4078:  v5 (tag 2.5.4)
      # 2292:  v4 (tag 2.3.6)
      # 1754:  v3 (tag 2.3.0)
      # 534:   v2 (shows up in 2.1.0, our first tag)


      def initialize

        @launch_time = Time.now

        @metric_ids = {}
        @histogram = NewRelic::Histogram.new(NewRelic::Control.instance.apdex_t / 10)
        @stats_engine = NewRelic::Agent::StatsEngine.new
        @transaction_sampler = NewRelic::Agent::TransactionSampler.new
        @stats_engine.transaction_sampler = @transaction_sampler
        @error_collector = NewRelic::Agent::ErrorCollector.new
        @connect_attempts = 0

        @request_timeout = NewRelic::Control.instance.fetch('timeout', 2 * 60)

        @last_harvest_time = Time.now
        @obfuscator = method(:default_sql_obfuscator)
      end

      module ClassMethods
        # Should only be called by NewRelic::Control
        def instance
          @instance ||= self.new
        end
      end

      module InstanceMethods

        attr_reader :obfuscator
        attr_reader :stats_engine
        attr_reader :transaction_sampler
        attr_reader :error_collector
        attr_reader :record_sql
        attr_reader :histogram
        attr_reader :metric_ids
        attr_reader :url_rules

        def record_transaction(duration_seconds, options={})
          is_error = options['is_error'] || options['error_message'] || options['exception']
          metric = options['metric']
          metric ||= options['uri'] # normalize this with url rules
          raise "metric or uri arguments required" unless metric
          metric_info = NewRelic::MetricParser::MetricParser.for_metric_named(metric)

          if metric_info.is_web_transaction?
            NewRelic::Agent::Instrumentation::MetricFrame.record_apdex(metric_info, duration_seconds, duration_seconds, is_error)
            histogram.process(duration_seconds)
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
              e = Exception.new options['error_message']
            else
              e = Exception.new 'Unknown Error'
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

          # @connected gets false after we fail to connect or have an error
          # connecting.  @connected has nil if we haven't finished trying to connect.
          # or we didn't attempt a connection because this is the master process

          # log.debug "Agent received after_fork notice in #$$: [#{control.agent_enabled?}; monitor=#{control.monitor_mode?}; connected: #{@connected.inspect}; thread=#{@worker_thread.inspect}]"
          return if !control.agent_enabled? or
            !control.monitor_mode? or
            @connected == false or
            @worker_thread && @worker_thread.alive?

          log.info "Starting the worker thread in #$$ after forking."

          # Clear out stats that are left over from parent process
          reset_stats

          # Don't ever check to see if this is a spawner.  If we're in a forked process
          # I'm pretty sure we're not also forking new instances.
          start_worker_thread(options)
          @stats_engine.start_sampler_thread
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

        # Attempt a graceful shutdown of the agent.
        def shutdown
          return if not started?
          if @worker_loop
            @worker_loop.stop

            log.debug "Starting Agent shutdown"

            # if litespeed, then ignore all future SIGUSR1 - it's
            # litespeed trying to shut us down

            if control.dispatcher == :litespeed
              Signal.trap("SIGUSR1", "IGNORE")
              Signal.trap("SIGTERM", "IGNORE")
            end

            begin
              NewRelic::Agent.disable_all_tracing do
                graceful_disconnect
              end
            rescue => e
              log.error e
              log.error e.backtrace.join("\n")
            end
          end
          @started = nil
        end

        def start_transaction
          @stats_engine.start_transaction
        end

        def end_transaction
          @stats_engine.end_transaction
        end

        def set_record_sql(should_record)
          prev = Thread::current[:record_sql]
          Thread::current[:record_sql] = should_record
          prev.nil? || prev
        end

        def set_record_tt(should_record)
          prev = Thread::current[:record_tt]
          Thread::current[:record_tt] = should_record
          prev.nil? || prev
        end
        # Push flag indicating whether we should be tracing in this
        # thread.
        def push_trace_execution_flag(should_trace=false)
          (Thread.current[:newrelic_untraced] ||= []) << should_trace
        end

        # Pop the current trace execution status.  Restore trace execution status
        # to what it was before we pushed the current flag.
        def pop_trace_execution_flag
          Thread.current[:newrelic_untraced].pop if Thread.current[:newrelic_untraced]
        end

        def set_sql_obfuscator(type, &block)
          if type == :before
            @obfuscator = NewRelic::ChainedCall.new(block, @obfuscator)
          elsif type == :after
            @obfuscator = NewRelic::ChainedCall.new(@obfuscator, block)
          elsif type == :replace
            @obfuscator = block
          else
            fail "unknown sql_obfuscator type #{type}"
          end
        end

        def log
          NewRelic::Agent.logger
        end
        
        # Herein lies the corpse of the former 'start' method. May
        # it's unmatched flog score rest in pieces.
        module Start
          def already_started?
            if started?
              control.log!("Agent Started Already!", :error)
              true
            end
          end

          def disabled?
            !control.agent_enabled?
          end
          
          def log_dispatcher
            dispatcher_name = control.dispatcher.to_s
            return if log_if(dispatcher_name.empty?, :info, "No dispatcher detected.")
            log.info "Dispatcher: #{dispatcher_name}"
          end
          
          def log_app_names
            log.info "Application: #{control.app_names.join(", ")}"
          end

          def apdex_f
            (4 * NewRelic::Control.instance.apdex_t).to_f
          end

          def apdex_f_threshold?
            sampler_config.fetch('transaction_threshold', '') =~ /apdex_f/i            
          end

          def set_sql_recording!
            record_sql_config = sampler_config.fetch('record_sql', :obfuscated)
            case record_sql_config.to_s
            when 'off'
              @record_sql = :off
            when 'none'
              @record_sql = :off
            when 'false'
              @record_sql = :off
            when 'raw'
              @record_sql = :raw
            else
              @record_sql = :obfuscated
            end
            
            log_sql_transmission_warning?
          end

          def log_sql_transmission_warning?
            log_if((@record_sql == :raw), :warn, "Agent is configured to send raw SQL to RPM service")
          end

          def sampler_config
            control.fetch('transaction_tracer', {})
          end
          
          # this entire method should be done on the transaction
          # sampler object, rather than here. We should pass in the
          # sampler config.
          def config_transaction_tracer
            @should_send_samples = @config_should_send_samples = sampler_config.fetch('enabled', true)
            @should_send_random_samples = sampler_config.fetch('random_sample', false)
            @explain_threshold = sampler_config.fetch('explain_threshold', 0.5).to_f
            @explain_enabled = sampler_config.fetch('explain_enabled', true)
            set_sql_recording!
            
            # default to 2.0, string 'apdex_f' will turn into your
            # apdex * 4
            @slowest_transaction_threshold = sampler_config.fetch('transaction_threshold', 2.0).to_f
            @slowest_transaction_threshold = apdex_f if apdex_f_threshold?
          end

          def connect_in_foreground
            NewRelic::Agent.disable_all_tracing { connect(:keep_retrying => false) }
          end

          def using_rubinius?
            RUBY_VERSION =~ /rubinius/i            
          end
          
          def using_jruby?
            defined?(JRuby) 
          end
          
          def using_sinatra?
            defined?(Sinatra::Application)
          end
          
          # we should not set an at_exit block if people are using
          # these as they don't do standard at_exit behavior per MRI/YARV
          def weird_ruby?
            using_rubinius? || using_jruby? || using_sinatra?
          end
          
          def install_exit_handler
            if control.send_data_on_exit && !weird_ruby?
              # Our shutdown handler needs to run after other shutdown handlers
              at_exit { at_exit { shutdown } }
            end
          end

          def notify_log_file_location
            log_file = NewRelic::Control.instance.log_file
            log_if(log_file, :info, "Agent Log found in #{log_file}")
          end

          def log_version_and_pid
            log.info "New Relic RPM Agent #{NewRelic::VERSION::STRING} Initialized: pid = #{$$}"
          end
          
          def log_if(boolean, level, message)
            self.log.send(level, message) if boolean
            boolean
          end

          def log_unless(boolean, level, message)
            self.log.send(level, message) unless boolean
            boolean
          end
          
          def monitoring?
            log_unless(control.monitor_mode?, :warn, "Agent configured not to send data in this environment - edit newrelic.yml to change this")
          end

          def has_license_key?
            log_unless(control.license_key, :error, "No license key found.  Please edit your newrelic.yml file and insert your license key.")
          end

          def has_correct_license_key?
            has_license_key? && correct_license_length
          end
          
          def correct_license_length
            key = control.license_key
            log_unless((key.length == 40), :error, "Invalid license key: #{key}")
          end

          def using_forking_dispatcher?
            log_if([:passenger, :unicorn].include?(control.dispatcher), :info, "Connecting workers after forking.")
          end
            
          def check_config_and_start_agent
            return unless monitoring? && has_correct_license_key?
            return if using_forking_dispatcher?
            connect_in_foreground if control.sync_startup
            start_worker_thread
            install_exit_handler
          end
        end

        include Start

        def start
          return if already_started? || disabled?
          @started = true
          @local_host = determine_host
          log_dispatcher
          log_app_names
          config_transaction_tracer
          check_config_and_start_agent
          log_version_and_pid
          notify_log_file_location
        end

        # Clear out the metric data, errors, and transaction traces.  Reset the histogram data.
        def reset_stats
          @stats_engine.reset_stats
          @unsent_errors = []
          @traces = nil
          @unsent_timeslice_data = {}
          @last_harvest_time = Time.now
          @launch_time = Time.now
          @histogram = NewRelic::Histogram.new(NewRelic::Control.instance.apdex_t / 10)
        end

        private
        def collector
          @collector ||= control.server
        end

        module StartWorkerThread

          def check_transaction_sampler_status
            # disable transaction sampling if disabled by the server
            # and we're not in dev mode
            if control.developer_mode? || @should_send_samples
              @transaction_sampler.enable
            else
              @transaction_sampler.disable
            end
          end

          def log_worker_loop_start
            log.info "Reporting performance data every #{@report_period} seconds."
            log.debug "Running worker loop"
          end

          def create_and_run_worker_loop
            @worker_loop = WorkerLoop.new
            @worker_loop.run(@report_period) do
              harvest_and_send_timeslice_data
              harvest_and_send_slowest_sample if @should_send_samples
              harvest_and_send_errors if error_collector.enabled
            end
          end

          def handle_force_restart(error)
            log.info error.message
            # disconnect and start over.
            # clear the stats engine
            reset_stats
            @metric_ids = {}
            @connected = nil
            # Wait a short time before trying to reconnect
            sleep 30
          end

          def handle_force_disconnect(error)
            # when a disconnect is requested, stop the current thread, which
            # is the worker thread that gathers data and talks to the
            # server.
            log.error "RPM forced this agent to disconnect (#{error.message})"
            disconnect
          end

          def handle_server_connection_problem(error)
            log.error "Unable to establish connection with the server.  Run with log level set to debug for more information."
            log.debug("#{error.class.name}: #{error.message}\n#{error.backtrace.first}")
            disconnect
          end

          def handle_other_error(error)
            log.error "Terminating worker loop: #{error.class.name}: #{error.message}\n  #{error.backtrace.join("\n  ")}"
            disconnect
          end

          def catch_errors
            yield
          rescue NewRelic::Agent::ForceRestartException => e
            handle_force_restart(e)
            retry
          rescue NewRelic::Agent::ForceDisconnectException => e
            handle_force_disconnect(e)
          rescue NewRelic::Agent::ServerConnectionException => e
            handle_server_connection_problem(e)
          rescue Exception => e
            handle_other_error(e)
          end
          
          def deferred_work!(connection_options)
            catch_errors do
              NewRelic::Agent.disable_all_tracing do
                # We try to connect.  If this returns false that means
                # the server rejected us for a licensing reason and we should
                # just exit the thread.  If it returns nil
                # that means it didn't try to connect because we're in the master.
                connect(connection_options)
                if @connected
                  check_transaction_sampler_status
                  log_worker_loop_start
                  create_and_run_worker_loop
                else
                  log.debug "No connection.  Worker thread ending."
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
          log.debug "Creating RPM worker thread."
          @worker_thread = Thread.new do
            deferred_work!(connection_options)
          end # thread new
          @worker_thread['newrelic_label'] = 'Worker Loop'
        end

        def control
          NewRelic::Control.instance
        end
        
        module Connect
          attr_accessor :connect_retry_period
          attr_accessor :connect_attempts

          def disconnect
            @connected = false
            true
          end

          def tried_to_connect?(options)
            !(@connected.nil? || options[:force_reconnect])
          end

          def should_keep_retrying?(options)
            @keep_retrying = (options[:keep_retrying].nil? || options[:keep_retrying])
          end

          def get_retry_period
            return 600 if self.connect_attempts > 6
            connect_attempts * 60
          end

          def increment_retry_period!
            self.connect_retry_period=(get_retry_period)
          end

          def should_retry?
            if @keep_retrying
              self.connect_attempts=(connect_attempts + 1)
              increment_retry_period!
              log.info "Will re-attempt in #{connect_retry_period} seconds"
              true
            else
              disconnect
              false
            end
          end

          def log_error(error)
            log.error "Error establishing connection with New Relic RPM Service at #{control.server}: #{error.message}"
            log.debug error.backtrace.join("\n")
          end

          def handle_license_error(error)
            log.error error.message
            log.info "Visit NewRelic.com to obtain a valid license key, or to upgrade your account."
            disconnect
          end
          
          def log_seed_token
            if control.validate_seed
              log.debug "Connecting with validation seed/token: #{control.validate_seed}/#{control.validate_token}"
            end
          end

          def environment_for_connect
            control['send_environment_info'] != false ? control.local_env.snapshot : []
          end

          def validate_settings
            {
              :seed => control.validate_seed,
              :token => control.validate_token
            }
          end

          def connect_settings
            {
              :pid => $$,
              :host => @local_host,
              :app_name => control.app_names,
              :language => 'ruby',
              :agent_version => NewRelic::VERSION::STRING,
              :environment => environment_for_connect,
              :settings => control.settings,
              :validate => validate_settings
            }
          end
          def connect_to_server
            log_seed_token
            connect_data = invoke_remote(:connect, connect_settings)
          end

          def configure_error_collector!(server_enabled)
            # Ask for permission to collect error data
            enabled = if error_collector.config_enabled && server_enabled
                        error_collector.enabled = true
                      else
                        error_collector.enabled = false
                      end
            log.debug "Errors will #{enabled ? '' : 'not '}be sent to the RPM service."
          end
          
          def enable_random_samples!(sample_rate)
            @transaction_sampler.random_sampling = true
            @transaction_sampler.sampling_rate = sample_rate
            log.info "Transaction sampling enabled, rate = #{@transaction_sampler.sampling_rate}"
          end
          

          def configure_transaction_tracer!(server_enabled, sample_rate)
            # Ask the server for permission to send transaction samples.
            # determined by subscription license.
            @should_send_samples = @config_should_send_samples && server_enabled

            if @should_send_samples
              # I don't think this is ever true, but...
              enable_random_samples!(sample_rate) if @should_send_random_samples
              log.debug "Transaction tracing threshold is #{@slowest_transaction_threshold} seconds."
            else
              log.debug "Transaction traces will not be sent to the RPM service."
            end
          end

          def set_collector_host!
            host = invoke_remote(:get_redirect_host)
            if host
              @collector = control.server_from_host(host)
            end
          end

          def query_server_for_configuration
            set_collector_host!
            
            finish_setup(connect_to_server)
          end
          def finish_setup(config_data)
            @agent_id = config_data['agent_run_id']
            @report_period = config_data['data_report_period']
            @url_rules = config_data['url_rules']

            log_connection!(config_data)
            configure_transaction_tracer!(config_data['collect_traces'], config_data['sample_rate'])
            configure_error_collector!(config_data['collect_errors'])
          end

          def log_connection!(config_data)
            control.log! "Connected to NewRelic Service at #{@collector}"
            log.debug "Agent Run       = #{@agent_id}."
            log.debug "Connection data = #{config_data.inspect}"
          end
        end
        include Connect

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
        #   agent run and RPM sees it as a separate instance (default is false).
        def connect(options)
          # Don't proceed if we already connected (@connected=true) or if we tried
          # to connect and were rejected with prejudice because of a license issue
          # (@connected=false), unless we're forced to by force_reconnect.
          return if tried_to_connect?(options)

          # wait a few seconds for the web server to boot, necessary in development
          @connect_retry_period = should_keep_retrying?(options) ? 10 : 0

          sleep connect_retry_period
          log.debug "Connecting Process to RPM: #$0"
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

        def determine_host
          Socket.gethostname
        end

        def determine_home_directory
          control.root
        end

        def is_application_spawner?
          $0 =~ /ApplicationSpawner|^unicorn\S* master/
        end

        def harvest_and_send_timeslice_data

          NewRelic::Agent::BusyCalculator.harvest_busy

          now = Time.now

          @unsent_timeslice_data ||= {}
          @unsent_timeslice_data = @stats_engine.harvest_timeslice_data(@unsent_timeslice_data, @metric_ids)

          begin
            # In this version of the protocol, we get back an assoc array of spec to id.
            metric_ids = invoke_remote(:metric_data, @agent_id,
                                       @last_harvest_time.to_f,
                                       now.to_f,
                                       @unsent_timeslice_data.values)

          rescue Timeout::Error
            # assume that the data was received. chances are that it was
            metric_ids = nil
          end

          metric_ids.each do | spec, id |
            @metric_ids[spec] = id
          end if metric_ids

          log.debug "#{now}: sent #{@unsent_timeslice_data.length} timeslices (#{@agent_id}) in #{Time.now - now} seconds"

          # if we successfully invoked this web service, then clear the unsent message cache.
          @unsent_timeslice_data = {}
          @last_harvest_time = now

          # handle_messages

          # note - exceptions are logged in invoke_remote.  If an exception is encountered here,
          # then the metric data is downsampled for another timeslices
        end

        def harvest_and_send_slowest_sample
          @traces = @transaction_sampler.harvest(@traces, @slowest_transaction_threshold)

          unless @traces.empty?
            now = Time.now
            log.debug "Sending (#{@traces.length}) transaction traces"
            begin
              # take the traces and prepare them for sending across the
              # wire.  This includes gathering SQL explanations, stripping
              # out stack traces, and normalizing SQL.  note that we
              # explain only the sql statements whose segments' execution
              # times exceed our threshold (to avoid unnecessary overhead
              # of running explains on fast queries.)
              options = { :keep_backtraces => true }
              options[:record_sql] = @record_sql unless @record_sql == :off
              options[:explain_sql] = @explain_threshold if @explain_enabled
              traces = @traces.collect {|trace| trace.prepare_to_send(options)}
              invoke_remote :transaction_sample_data, @agent_id, traces
            rescue PostTooBigException
              # we tried to send too much data, drop the first trace and
              # try again
              retry if @traces.shift
            end

            log.debug "Sent slowest sample (#{@agent_id}) in #{Time.now - now} seconds"
          end

          # if we succeed sending this sample, then we don't need to keep
          # the slowest sample around - it has been sent already and we
          # can collect the next one
          @traces = nil

          # note - exceptions are logged in invoke_remote.  If an
          # exception is encountered here, then the slowest sample of is
          # determined of the entire period since the last reported
          # sample.
        end

        def harvest_and_send_errors
          @unsent_errors = @error_collector.harvest_errors(@unsent_errors)
          if @unsent_errors && @unsent_errors.length > 0
            log.debug "Sending #{@unsent_errors.length} errors"
            begin
              invoke_remote :error_data, @agent_id, @unsent_errors
            rescue PostTooBigException
              @unsent_errors.shift
              retry
            end
            # if the remote invocation fails, then we never clear
            # @unsent_errors, and therefore we can re-attempt to send on
            # the next heartbeat.  Note the error collector maxes out at
            # 20 instances to prevent leakage
            @unsent_errors = []
          end
        end

        def compress_data(object)
          dump = Marshal.dump(object)

          # this checks to make sure mongrel won't choke on big uploads
          check_post_size(dump)

          # we currently optimize for CPU here since we get roughly a 10x
          # reduction in message size with this, and CPU overhead is at a
          # premium. For extra-large posts, we use the higher compression
          # since otherwise it actually errors out.

          dump_size = dump.size

          # Compress if content is smaller than 64kb.  There are problems
          # with bugs in Ruby in some versions that expose us to a risk of
          # segfaults if we compress aggressively.
          return [dump, 'identity'] if dump_size < (64*1024)

          # medium payloads get fast compression, to save CPU
          # big payloads get all the compression possible, to stay under
          # the 2,000,000 byte post threshold
          compression = dump_size < 2000000 ? Zlib::BEST_SPEED : Zlib::BEST_COMPRESSION

          [Zlib::Deflate.deflate(dump, compression), 'deflate']
        end

        def check_post_size(post_string)
          # TODO: define this as a config option on the server side
          return if post_string.size < control.post_size_limit
          log.warn "Tried to send too much data: #{post_string.size} bytes"
          raise PostTooBigException
        end

        def send_request(opts)
          request = Net::HTTP::Post.new(opts[:uri], 'CONTENT-ENCODING' => opts[:encoding], 'HOST' => opts[:collector].name)
          request.content_type = "application/octet-stream"
          request.body = opts[:data]

          log.debug "Connect to #{opts[:collector]}#{opts[:uri]}"

          response = nil
          http = control.http_connection(collector)
          http.read_timeout = nil
          begin
            NewRelic::TimerLib.timeout(@request_timeout) do
              response = http.request(request)
            end
          rescue Timeout::Error
            log.warn "Timed out trying to post data to RPM (timeout = #{@request_timeout} seconds)" unless @request_timeout < 30
            raise
          end
          if response.is_a? Net::HTTPServiceUnavailable
            raise NewRelic::Agent::ServerConnectionException, "Service unavailable (#{response.code}): #{response.message}"
          elsif response.is_a? Net::HTTPGatewayTimeOut
            log.debug("Timed out getting response: #{response.message}")
            raise Timeout::Error, response.message
          elsif response.is_a? Net::HTTPRequestEntityTooLarge
            raise PostTooBigException
          elsif !(response.is_a? Net::HTTPSuccess)
            raise NewRelic::Agent::ServerConnectionException, "Unexpected response from server (#{response.code}): #{response.message}"
          end
          response
        end

        def decompress_response(response)
          if response['content-encoding'] != 'gzip'
            log.debug "Uncompressed content returned"
            return response.body
          end
          log.debug "Decompressing return value"
          i = Zlib::GzipReader.new(StringIO.new(response.body))
          i.read
        end

        def check_for_exception(response)
          dump = decompress_response(response)
          value = Marshal.load(dump)
          raise value if value.is_a? Exception
          value
        end

        def remote_method_uri(method)
          uri = "/agent_listener/#{PROTOCOL_VERSION}/#{control.license_key}/#{method}"
          uri << "?run_id=#{@agent_id}" if @agent_id
          uri
        end

        # send a message via post
        def invoke_remote(method, *args)
          #determines whether to zip the data or send plain
          post_data, encoding = compress_data(args)

          response = send_request({:uri => remote_method_uri(method), :encoding => encoding, :collector => collector, :data => post_data})

          # raises the right exception if the remote server tells it to die
          return check_for_exception(response)
        rescue NewRelic::Agent::ForceRestartException => e
          log.info e.message
          raise
        rescue SystemCallError, SocketError => e
          # These include Errno connection errors
          raise NewRelic::Agent::ServerConnectionException, "Recoverable error connecting to the server: #{e}"
        end

        def graceful_disconnect
          if @connected
            begin
              @request_timeout = 10
              log.debug "Flushing unsent metric data to server"
              @worker_loop.run_task
              if @connected_pid == $$
                log.debug "Sending RPM service agent run shutdown message"
                invoke_remote :shutdown, @agent_id, Time.now.to_f
              else
                log.debug "This agent connected from parent process #{@connected_pid}--not sending shutdown"
              end
              log.debug "Graceful disconnect complete"
            rescue Timeout::Error, StandardError
            end
          else
            log.debug "Bypassing graceful disconnect - agent not connected"
          end
        end
        def default_sql_obfuscator(sql)
          sql = sql.dup
          # This is hardly readable.  Use the unit tests.
          # remove single quoted strings:
          sql.gsub!(/'(.*?[^\\'])??'(?!')/, '?')
          # remove double quoted strings:
          sql.gsub!(/"(.*?[^\\"])??"(?!")/, '?')
          # replace all number literals
          sql.gsub!(/\d+/, "?")
          sql
        end
      end

      extend ClassMethods
      include InstanceMethods
    end
  end
end
