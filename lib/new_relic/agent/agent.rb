require 'socket'
require 'net/https' 
require 'net/http'
require 'logger'
require 'singleton'
require 'zlib'
require 'stringio'

# The NewRelic Agent collects performance data from ruby applications in realtime as the
# application runs, and periodically sends that data to the NewRelic server.
module NewRelic::Agent
  # an exception that is thrown by the server if the agent license is invalid
  class LicenseException < StandardError; end
  
  # an exception that forces an agent to stop reporting until its mongrel is restarted
  class ForceDisconnectException < StandardError; end
  
  class IgnoreSilentlyException < StandardError; end
  
  # Reserved for future use
  class ServerError < StandardError; end
  
  class BackgroundLoadingError < StandardError; end

  # add some convenience methods for easy access to the Agent singleton.
  # the following static methods all point to the same Agent instance:
  #
  # NewRelic::Agent.agent
  # NewRelic::Agent.instance
  # NewRelic::Agent::Agent.instance
  class << self
    def agent
      NewRelic::Agent::Agent.instance
    end
    
    alias instance agent
    
    # Get or create a statistics gatherer that will aggregate numerical data
    # under a metric name.
    #
    # metric_name should follow a slash separated path convention.  Application
    # specific metrics should begin with "Custom/".
    #
    # the statistical gatherer returned by get_stats accepts data
    # via calls to add_data_point(value)
    def get_stats(metric_name, use_scope=false)
      agent.stats_engine.get_stats(metric_name, use_scope)
    end

    def get_stats_no_scope(metric_name)
      agent.stats_engine.get_stats_no_scope(metric_name)
    end
    
    
    # Call this to manually start the Agent in situations where the Agent does
    # not auto-start.
    # When the app environment loads, so does the Agent. However, the Agent will
    # only connect to RPM if a web front-end is found. If you want to selectively monitor
    # ruby processes that don't use web plugins, then call this method in your
    # code and the Agent will fire up and start reporting to RPM.
    #
    # environment - the name of the environment. used for logging only
    # port - the name of this instance. shows up in the RPM UI screens. can be any String
    #
    def manual_start(environment, identifier)
      agent.manual_start(environment, identifier)
    end
    
    # This method sets the block sent to this method as a sql obfuscator. 
    # The block will be called with a single String SQL statement to obfuscate.
    # The method must return the obfuscated String SQL. 
    # If chaining of obfuscators is required, use type = :before or :after
    #
    # type = :before, :replace, :after
    #
    # example:
    #    NewRelic::Agent.set_sql_obfuscator(:replace) do |sql|
    #       my_obfuscator(sql)
    #    end
    # 
    def set_sql_obfuscator(type = :replace, &block)
      agent.set_sql_obfuscator type, &block
    end
    
    
    # This method sets the state of sql recording in the transaction
    # sampler feature. Within the given block, no sql will be recorded
    #
    # usage:
    #
    #   NewRelic::Agent.disable_sql_recording do
    #     ...  
    #    end
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
    # block.
    def disable_transaction_tracing
      state = agent.set_record_tt(false)
      begin
        yield
      ensure
        agent.set_record_tt(state)
      end
    end
    
    # This method allows a filter to be applied to errors that RPM will track.
    # The block should return the exception to track (which could be different from
    # the original exception) or nil to ignore this exception
    #
    def ignore_error_filter(&block)
      agent.error_collector.ignore_error_filter(&block)
    end
    
    # Add parameters to the current transaction trace
    #
    def add_custom_parameters(params)
      agent.add_custom_parameters(params)
    end
    
    alias add_request_parameters add_custom_parameters
    
  end 
  
  # Implementation default for the NewRelic Agent
  class Agent
    # Specifies the version of the agent's communication protocol
    # with the NewRelic hosted site.
    
    PROTOCOL_VERSION = 5
    
    include Singleton
    
    # Config object
    attr_accessor :config
    attr_reader :obfuscator
    attr_reader :stats_engine
    attr_reader :transaction_sampler
    attr_reader :error_collector
    attr_reader :worker_loop
    attr_reader :license_key
    attr_reader :record_sql
    attr_reader :identifier
    
    # This method is deprecated.  Use start.
    def manual_start(environment, identifier)
      start(environment, identifier, true)
    end
    
    # Start up the agent, which will connect to the newrelic server and start 
    # reporting performance information.  Typically this is done from the
    # environment configuration file.  
    # environment identifies the host environment, like mongrel, thin, or take.
    # identifier is an identifier which uniquely identifies the process hosting
    # the agent.  It should be ideally something like a server port, like 3000,
    # a handler thread name, or a script name.  It should not be a PID because 
    # that will change
    # from invocation to invocation.  For something like rake, you could use
    # the task name.
    # Return false if the agent was not started
    def start(environment, identifier, force=false)
      
      if @started
        config.log! "Agent Started Already!"
        return
      end
      @environment = environment
      @identifier = identifier && identifier.to_s
      if @identifier
        start_reporting(force)
        config.log! "New Relic RPM Agent #{NewRelic::VERSION::STRING} Initialized: pid = #{$$}, handler = #{@environment}"
        config.log! "Agent Log is found in #{NewRelic::Config.instance.log_file}"
        return true
      else
        return false
      end
    end
    
    # this method makes sure that the agent is running. it's important
    # for passenger where processes are forked and the agent is dormant
    #
    def ensure_worker_thread_started
      return unless @prod_mode_enabled && !@invalid_license
      if @worker_loop.nil? || @worker_loop.pid != $$
        launch_worker_thread
        @stats_engine.spawn_sampler_thread
      end
    end
    
    # True if we have initialized and completed 'start_reporting'
    def started?
      @started
    end
    
    
    # Attempt a graceful shutdown of the agent.  
    def shutdown
      return if !@started
      if @worker_loop
        @worker_loop.stop
        
        log.debug "Starting Agent shutdown"
        
        # if litespeed, then ignore all future SIGUSR1 - it's litespeed trying to shut us down
        
        if @environment == :litespeed
          Signal.trap("SIGUSR1", "IGNORE")
          Signal.trap("SIGTERM", "IGNORE")
        end
        
        begin
          graceful_disconnect
        rescue => e
          log.error e
          log.error e.backtrace.join("\n")
        end
      end
      @started = nil
    end
    
    def start_transaction
      Thread::current[:custom_params] = nil
      @stats_engine.start_transaction
    end
    
    def end_transaction
      Thread::current[:custom_params] = nil
      @stats_engine.end_transaction
    end
    
    def set_record_sql(should_record)
      prev = Thread::current[:record_sql]
      Thread::current[:record_sql] = should_record
      
      prev || true
    end
    
    def set_record_tt(should_record)
      prev = Thread::current[:record_tt]
      Thread::current[:record_tt] = should_record
      
      prev || true
    end
    
    def add_custom_parameters(params)
      p = Thread::current[:custom_params] || (Thread::current[:custom_params] = {})
      
      p.merge!(params)
    end
    
    def custom_params
      Thread::current[:custom_params] || {}
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
    
    def instrument_app
      return if @instrumented
      
      @instrumented = true
      
      # Instrumentation for the key code points inside rails for monitoring by NewRelic.
      # note this file is loaded only if the newrelic agent is enabled (through config/newrelic.yml)
      instrumentation_path = File.join(File.dirname(__FILE__), 'instrumentation')
      instrumentation_files = [ ] <<
      File.join(instrumentation_path, '*.rb') <<
      File.join(instrumentation_path, config.app.to_s, '*.rb')
      instrumentation_files.each do | pattern |
        Dir.glob(pattern) do |file|
          begin
            log.debug "Processing instrumentation file '#{file}'"
            require file
          rescue => e
            log.error "Error loading instrumentation file '#{file}': #{e}"
            log.debug e.backtrace.join("\n")
          end
        end
      end
      
      log.debug "Finished instrumentation"
    end
    
    def log
      setup_log unless @log
      @log
    end
    
    def apdex_t
      @apdex_t ||= config['apdex_t'].to_f
    end    
        
    private
    
    # Connect to the server, and run the worker loop forever.  Will not return.
    def run_worker_loop

      # connect to the server.  this will keep retrying until successful or
      # it determines the license is bad.
      connect
      
      # We may not be connected now but keep going for dev mode
      if @connected
        begin
          # determine the reporting period (server based)
          # note if the agent attempts to report more frequently than the specified
          # report data, then it will be ignored.
          
          config.log! "Reporting performance data every #{@report_period} seconds"        
          @worker_loop.add_task(@report_period) do 
            harvest_and_send_timeslice_data
          end
          
          if @should_send_samples && @use_transaction_sampler
            @worker_loop.add_task(@report_period) do 
              harvest_and_send_slowest_sample
            end
          elsif !config.developer_mode?
            # We still need the sampler for dev mode.
            @transaction_sampler.disable
          end
          
          if @should_send_errors && @error_collector.enabled
            @worker_loop.add_task(@report_period) do 
              harvest_and_send_errors
            end
          end
          @worker_loop.run
        rescue StandardError
          @connected = false
          raise
        end
      end
    end
    
    def launch_worker_thread
      if (@environment == :passenger && $0 =~ /ApplicationSpawner/)
        log.info "Process is passenger spawner - don't connect to RPM service"
        return
      end
      
      @worker_loop = WorkerLoop.new(log)
      
      if config['check_bg_loading']
        require 'new_relic/agent/patch_const_missing'
        log.warn "Agent background loading checking turned on"
        ClassLoadingWatcher.enable_warning
      end
      
      @worker_thread = Thread.new do
        begin
          ClassLoadingWatcher.set_background_thread(Thread.current) if config['check_bg_loading']
          run_worker_loop
        rescue IgnoreSilentlyException
          config.log! "Unable to establish connection with the server.  Run with log level set to debug for more information."
        rescue StandardError => e
          config.log! e
          config.log! e.backtrace.join("\n")
        end
      end
      
      # This code should be activated to check that no dependency loading is occuring in the background thread
      # by stopping the foreground thread after the background thread is created. Turn on dependency loading logging
      # and make sure that no loading occurs.
      #
      #      config.log! "FINISHED AGENT INIT"
      #      while true
      #        sleep 1
      #      end
      
    end    
    def start_reporting(force_enable=false)
      @local_host = determine_host
      
      setup_log
      
      if @environment == :passenger
        log.warn "Phusion Passenger has been detected. Some RPM memory statistics may have inaccuracies due to short process lifespans"
      end
      
      @started = true
      
      @license_key = config.fetch('license_key', nil)
      
      error_collector_config = config.fetch('error_collector', {})
      
      @error_collector.enabled = error_collector_config.fetch('enabled', true)
      @error_collector.capture_source = error_collector_config.fetch('capture_source', true)
      
      log.info "Error collector is enabled in agent config" if @error_collector.enabled
      
      ignore_errors = error_collector_config.fetch('ignore_errors', "")
      ignore_errors = ignore_errors.split(",")
      ignore_errors.each { |error| error.strip! } 
      
      @error_collector.ignore(ignore_errors)
      
      @capture_params = config.fetch('capture_params', false)
      
      sampler_config = config.fetch('transaction_tracer', {})
      
      @use_transaction_sampler = sampler_config.fetch('enabled', false)
      @record_sql = (sampler_config.fetch('record_sql', 'obfuscated') || 'off').intern
      @slowest_transaction_threshold = sampler_config.fetch('transaction_threshold', '2.0').to_f
      @explain_threshold = sampler_config.fetch('explain_threshold', '0.5').to_f
      @explain_enabled = sampler_config.fetch('explain_enabled', true)
      @stack_trace_threshold = sampler_config.fetch('stack_trace_threshold', '0.500').to_f
      
      log.info "Transaction tracing is enabled in agent config" if @use_transaction_sampler
      log.warn "Agent is configured to send raw SQL to RPM service" if @record_sql == :raw
      
      @prod_mode_enabled = force_enable || config['enabled']
      
      # Initialize transaction sampler
      TransactionSampler.capture_params = @capture_params
      @transaction_sampler.stack_trace_threshold = @stack_trace_threshold
      @error_collector.capture_params = @capture_params
      
      
      # make sure the license key exists and is likely to be really a license key
      # by checking it's string length (license keys are 40 character strings.)
      if @prod_mode_enabled && (!@license_key || @license_key.length != 40)
        config.log! "No license key found.  Please edit your newrelic.yml file and insert your license key"
        return
      end
      
      instrument_app
      
      if @prod_mode_enabled
        load_samplers
        launch_worker_thread
        # When the VM shuts down, attempt to send a message to the server that
        # this agent run is stopping, assuming it has successfully connected
        at_exit { shutdown }
      end
      
      log.debug "Finished starting reporting"
    end
    def initialize
      @connected = false
      @launch_time = Time.now
      
      @metric_ids = {}
      @environment = :unknown
      
      @config = NewRelic::Config.instance
      
      @stats_engine = NewRelic::Agent::StatsEngine.new
      @transaction_sampler = NewRelic::Agent::TransactionSampler.new(self)
      @error_collector = NewRelic::Agent::ErrorCollector.new(self)
      
      @request_timeout = NewRelic::Config.instance.fetch('timeout', 2 * 60)
      
      @invalid_license = false
      
      @last_harvest_time = Time.now
    end
    
    def setup_log
      @log = config.setup_log(identifier)
      log.info "Runtime environment: #{@environment.to_s}"
    end
    
    # Connect to the server and validate the license.
    # If successful, @connected has true when finished.
    # If not successful, you can keep calling this. 
    # Return false if we could not establish a connection with the
    # server and we should not retry, such as if there's
    # a bad license key.
    def connect
      # wait a few seconds for the web server to boot, necessary in development
      connect_retry_period = 5
      connect_attempts = 0
      
      begin
        sleep connect_retry_period.to_i
        @agent_id = invoke_remote :launch, 
            @local_host,
            @identifier, 
            determine_home_directory, 
            $$, 
            @launch_time.to_f, 
            NewRelic::VERSION::STRING, 
            config.app_config_info, 
            config['app_name'], 
            config.settings
        @report_period = invoke_remote :get_data_report_period, @agent_id
 
        config.log! "Connected to NewRelic Service at #{config.server}"
        log.debug "Agent ID = #{@agent_id}."
        
        # Ask the server for permission to send transaction samples.  determined by subscription license.
        @should_send_samples = invoke_remote :should_collect_samples, @agent_id
        
        # Ask for mermission to collect error data
        @should_send_errors = invoke_remote :should_collect_errors, @agent_id
        
        log.info "Transaction traces will be sent to the RPM service" if @use_transaction_sampler && @should_send_samples
        log.info "Errors will be sent to the RPM service" if @error_collector.enabled && @should_send_errors
        
        @connected = true
        
      rescue LicenseException => e
        config.log! e.message, :error
        config.log! "Visit NewRelic.com to obtain a valid license key, or to upgrade your account."
        @invalid_license = true
        return false
        
      rescue Timeout::Error, StandardError => e
        log.info "Unable to establish connection with New Relic RPM Service at #{config.server}"
        unless e.instance_of? IgnoreSilentlyException
          log.error e.message
          log.debug e.backtrace.join("\n")
        end
        # retry logic
        connect_attempts += 1
        case connect_attempts
          when 1..5
          connect_retry_period, period_msg = 5, nil
          when 6..10 then
          connect_retry_period, period_msg = 30, nil
          when 11..20 then
          connect_retry_period, period_msg = 1.minutes, "1 minute"
        else 
          connect_retry_period, period_msg = 10.minutes, "10 minutes"
        end
        log.info "Will re-attempt in #{period_msg}" if period_msg
        retry
      end
    end
      
    def load_samplers
      sampler_files = File.join(File.dirname(__FILE__), 'samplers', '*.rb')
      Dir.glob(sampler_files) do |file|
        begin
          require file
        rescue => e
          log.error "Error loading sampler '#{file}': #{e}"
        end
      end
    end
    
    def determine_host
      Socket.gethostname
    end
    
    def determine_home_directory
      config.root
    end
    
    def harvest_and_send_timeslice_data
      
      NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.harvest_busy
      
      now = Time.now
      
      # Fixme: remove the harvest thread tracking
      @harvest_thread ||= Thread.current
      
      if @harvest_thread != Thread.current
        config.log! "ERROR - two harvest threads are running (current=#{Thread.current}, havest=#{@harvest_thread}"
        @harvest_thread = Thread.current
      end
      
      # Fixme: remove this check
      config.log! "Agent sending data too frequently - #{now - @last_harvest_time} seconds" if (now.to_f - @last_harvest_time.to_f) < 45
      
      @unsent_timeslice_data ||= {}
      @unsent_timeslice_data = @stats_engine.harvest_timeslice_data(@unsent_timeslice_data, @metric_ids)
      
      begin
        metric_ids = invoke_remote(:metric_data, @agent_id, 
                                   @last_harvest_time.to_f, 
                                   now.to_f, 
                                   @unsent_timeslice_data.values)
        
      rescue Timeout::Error
        # assume that the data was received. chances are that it was
        metric_ids = nil
      end
      
      
      @metric_ids.merge! metric_ids if metric_ids
      
      log.debug "#{now}: sent #{@unsent_timeslice_data.length} timeslices (#{@agent_id}) in #{Time.now - now} seconds"
      
      # if we successfully invoked this web service, then clear the unsent message cache.
      @unsent_timeslice_data = {}
      @last_harvest_time = now
      
      # handle_messages 
      
      # note - exceptions are logged in invoke_remote.  If an exception is encountered here,
      # then the metric data is downsampled for another timeslices
    end
    
    def harvest_and_send_slowest_sample
      @slowest_sample = @transaction_sampler.harvest_slowest_sample(@slowest_sample)
      
      if @slowest_sample && @slowest_sample.duration > @slowest_transaction_threshold
        now = Time.now
        log.debug "Sending slowest sample: #{@slowest_sample.params[:path]}, #{@slowest_sample.duration.round_to(2)}s (explain=#{@explain_enabled})" if @slowest_sample
        
        # take the slowest sample, and prepare it for sending across the wire.  This includes
        # gathering SQL explanations, stripping out stack traces, and normalizing SQL.
        # note that we explain only the sql statements whose segments' execution times exceed 
        # our threshold (to avoid unnecessary overhead of running explains on fast queries.)
        sample = @slowest_sample.prepare_to_send(:explain_sql => @explain_threshold, :record_sql => @record_sql, :keep_backtraces => true, :explain_enabled => @explain_enabled)
        
        invoke_remote :transaction_sample_data, @agent_id, sample
        
        log.debug "#{now}: sent slowest sample (#{@agent_id}) in #{Time.now - now} seconds"
      end
      
      # if we succeed sending this sample, then we don't need to keep the slowest sample
      # around - it has been sent already and we can collect the next one
      @slowest_sample = nil
      
      # note - exceptions are logged in invoke_remote.  If an exception is encountered here,
      # then the slowest sample of is determined of the entire period since the last
      # reported sample.
    end
    
    def harvest_and_send_errors
      @unsent_errors = @error_collector.harvest_errors(@unsent_errors)
      if @unsent_errors && @unsent_errors.length > 0
        log.debug "Sending #{@unsent_errors.length} errors"
        
        invoke_remote :error_data, @agent_id, @unsent_errors
        
        # if the remote invocation fails, then we never clear @unsent_errors,
        # and therefore we can re-attempt to send on the next heartbeat.  Note
        # the error collector maxes out at 20 instances to prevent leakage
        @unsent_errors = []
      end
    end
    
    # send a message via post
    def invoke_remote(method, *args)
      # we currently optimize for CPU here since we get roughly a 10x reduction in
      # message size with this, and CPU overhead is at a premium.  If we wanted
      # to go for higher compression instead, we could use Zlib::BEST_COMPRESSION and 
      # pay a little more CPU.
      post_data = Zlib::Deflate.deflate(Marshal.dump(args), Zlib::BEST_SPEED)
      http = config.http_connection
      
      # params = {:method => method, :license_key => license_key, :protocol_version => PROTOCOL_VERSION }
      # uri = "/agent_listener/invoke_raw_method?#{params.to_query}"
      uri = "/agent_listener/invoke_raw_method?method=#{method}&license_key=#{license_key}&protocol_version=#{PROTOCOL_VERSION}"
      uri += "&run_id=#{@agent_id}" if @agent_id
      
      request = Net::HTTP::Post.new(uri, 'ACCEPT-ENCODING' => 'gzip')
      request.content_type = "application/octet-stream"
      request.body = post_data
      
      log.debug "#{uri}"
      
      response = nil
      
      begin
        timeout(@request_timeout) do      
          response = http.request(request)
        end
      rescue Timeout::Error
        log.warn "Timed out trying to post data to RPM (timeout = #{@request_timeout} seconds)"
        raise IgnoreSilentlyException
      end
      
      if response.is_a? Net::HTTPSuccess
        body = nil
        if response['content-encoding'] == 'gzip'
          log.debug "Decompressing return value"
          i = Zlib::GzipReader.new(StringIO.new(response.body))
          body = i.read
        else
          log.debug "Uncompressed content returned"
          body = response.body
        end
        return_value = Marshal.load(body)
        if return_value.is_a? Exception
          raise return_value
        else
          return return_value
        end
      else
        log.debug "Unexpected response from server: #{response.code}: #{response.message}"
        raise IgnoreSilentlyException
      end 
    rescue ForceDisconnectException => e
      config.log! "RPM forced this agent to disconnect", :error
      config.log! e.message, :error
      config.log! "Restart this process to resume RPM's agent communication with NewRelic.com"
      # when a disconnect is requested, stop the current thread, which is the worker thread that 
      # gathers data and talks to the server. 
      @connected = false
      Thread.exit
    rescue SystemCallError, SocketError => e
      # These include Errno connection errors 
      log.debug "Recoverable error connecting to the server: #{e}"
      raise IgnoreSilentlyException
    end
    
    def graceful_disconnect
      if @connected && !(config.server.host == "localhost" && @identifier == '3000')
        begin
          log.debug "Sending graceful shutdown message to #{config.server}"
          
          @request_timeout = 5
          
          log.debug "Sending RPM service agent run shutdown message"
          invoke_remote :shutdown, @agent_id, Time.now.to_f
          
          log.debug "Graceful shutdown complete"
          
        rescue Timeout::Error, StandardError => e
        end
      else
        log.debug "Bypassing graceful shutdown - agent in development mode"
      end
    end
  end
  
end
