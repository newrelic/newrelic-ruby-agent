require 'socket'
require 'net/https' 
require 'net/http'
require 'logger'
require 'zlib'
require 'stringio'

# The NewRelic Agent collects performance data from ruby applications in realtime as the
# application runs, and periodically sends that data to the NewRelic server.
module NewRelic::Agent
 
  # The Agent is a singleton that is instantiated when the plugin is activated.
  class Agent
    
    # Specifies the version of the agent's communication protocol
    # with the NewRelic hosted site.
    
    PROTOCOL_VERSION = 5
    
    attr_reader :obfuscator
    attr_reader :stats_engine
    attr_reader :transaction_sampler
    attr_reader :error_collector
    attr_reader :worker_loop
    attr_reader :record_sql
    
    # Should only be called by NewRelic::Control
    def self.instance
      @instance ||= self.new
    end
    # This method is deprecated.  Use NewRelic::Agent.manual_start
    def manual_start(ignored=nil, also_ignored=nil)
      raise "This method no longer supported.  Instead use the class method NewRelic::Agent.manual_start"
    end
    
    # this method makes sure that the agent is running. it's important
    # for passenger where processes are forked and the agent is dormant
    #
    def ensure_worker_thread_started
      return unless control.agent_enabled? && control.monitor_mode? && !@invalid_license
      if !running? 
        launch_worker_thread
        @stats_engine.spawn_sampler_thread
      end
    end
    
    # True if the worker thread has been started.  Doesn't necessarily
    # mean we are connected 
    def running?
      control.agent_enabled? && control.monitor_mode? && @worker_loop && @worker_loop.pid == $$
    end
    
    # True if we have initialized and completed 'start'
    def started?
      @started
    end
    
    # Attempt a graceful shutdown of the agent.  
    def shutdown
      return if not started?
      if @worker_loop
        @worker_loop.stop
        
        log.debug "Starting Agent shutdown"
        
        # if litespeed, then ignore all future SIGUSR1 - it's litespeed trying to shut us down
        
        if control.dispatcher == :litespeed
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

    def log
      NewRelic::Control.instance.log
    end  
        
    # Start up the agent.  This verifies that the agent_enabled? is true
    # and initializes the sampler based on the current controluration settings.
    # Then it will fire up the background thread for sending data to the server if applicable.
    def start
      if started?
        control.log! "Agent Started Already!", :error
        return
      end
      return if !control.agent_enabled? 

      @local_host = determine_host
      
      log.info "Web container: #{control.dispatcher.to_s}"
      
      if control.dispatcher == :passenger
        log.warn "Phusion Passenger has been detected. Some RPM memory statistics may have inaccuracies due to short process lifespans."
      end
      
      @started = true
      
      sampler_config = control.fetch('transaction_tracer', {})
      @use_transaction_sampler = sampler_config.fetch('enabled', false)
      
      @record_sql = sampler_config.fetch('record_sql', :obfuscated).to_sym
      
      # use transaction_threshold: 4.0 to force the TT collection threshold to 4 seconds
      # use transaction_threshold: apdex_f to use your apdex t value multiplied by 4
      # undefined transaction_threshold defaults to 2.0
      apdex_f = 4 * NewRelic::Control.instance['apdex_t'].to_f
      @slowest_transaction_threshold = sampler_config.fetch('transaction_threshold', 2.0)
      if @slowest_transaction_threshold =~ /apdex_f/i
        @slowest_transaction_threshold = apdex_f
      elsif !@slowest_transaction_threshold.is_a? Float
        log.warn "Invalid transaction_threshold detected: '#{@slowest_transaction_threshold}'. Using #{apdex_f} seconds." if @use_transaction_sampler
        @slowest_transaction_threshold = apdex_f
      end
      @slowest_transaction_threshold = @slowest_transaction_threshold.to_f
      log.info "Transaction tracing threshold is #{@slowest_transaction_threshold} seconds" if @use_transaction_sampler
      
      @explain_threshold = sampler_config.fetch('explain_threshold', 0.5).to_f
      @explain_enabled = sampler_config.fetch('explain_enabled', true)
      @random_sample = sampler_config.fetch('random_sample', false)
      log.info "Transaction tracing is enabled in agent control" if @use_transaction_sampler
      log.warn "Agent is configured to send raw SQL to RPM service" if @record_sql == :raw
      # Initialize transaction sampler
      @transaction_sampler.random_sampling = @random_sample

      if control.monitor_mode?
        # make sure the license key exists and is likely to be really a license key
        # by checking it's string length (license keys are 40 character strings.)
        if !control.license_key
          @invalid_license = true
          control.log! "No license key found.  Please edit your newrelic.yml file and insert your license key.", :error
        elsif  control.license_key.length != 40
          @invalid_license = true
          control.log! "Invalid license key: #{control.license_key}", :error
        else     
          launch_worker_thread
          # When the VM shuts down, attempt to send a message to the server that
          # this agent run is stopping, assuming it has successfully connected
          at_exit { shutdown }
        end
      end
      control.log! "New Relic RPM Agent #{NewRelic::VERSION::STRING} Initialized: pid = #{$$}"
      control.log! "Agent Log found in #{NewRelic::Control.instance.log_file}"
    end

    private
    def collector
      @collector ||= control.server
    end
    
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
          
          control.log! "Reporting performance data every #{@report_period} seconds."        
          @worker_loop.add_task(@report_period) do 
            harvest_and_send_timeslice_data
          end
          
          if @should_send_samples && @use_transaction_sampler
            @worker_loop.add_task(@report_period) do 
              harvest_and_send_slowest_sample
            end
          elsif !control.developer_mode?
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
      if (control.dispatcher == :passenger && $0 =~ /ApplicationSpawner/)
        log.debug "Process is passenger spawner - don't connect to RPM service"
        return
      end
      
      @worker_loop = WorkerLoop.new(log)
      
      if control['check_bg_loading']
        log.warn "Agent background loading checking turned on"
        require 'new_relic/agent/patch_const_missing'
        ClassLoadingWatcher.enable_warning
      end
      
      @worker_thread = Thread.new do
        begin
          ClassLoadingWatcher.background_thread=Thread.current if control['check_bg_loading']
        
          run_worker_loop
        rescue IgnoreSilentlyException
          control.log! "Unable to establish connection with the server.  Run with log level set to debug for more information."
        rescue StandardError => e
          control.log! e, :error
          control.log! e.backtrace.join("\n  "), :error
        end
      end
      @worker_thread['newrelic_label'] = 'Worker Loop'
      
      # This code should be activated to check that no dependency loading is occuring in the background thread
      # by stopping the foreground thread after the background thread is created. Turn on dependency loading logging
      # and make sure that no loading occurs.
      #
      #      control.log! "FINISHED AGENT INIT"
      #      while true
      #        sleep 1
      #      end
    end
    
    def control
      NewRelic::Control.instance
    end
    
    def initialize
      @connected = false
      @launch_time = Time.now
      
      @metric_ids = {}
      
      @stats_engine = NewRelic::Agent::StatsEngine.new
      @transaction_sampler = NewRelic::Agent::TransactionSampler.new(self)
      @error_collector = NewRelic::Agent::ErrorCollector.new(self)
      
      @request_timeout = NewRelic::Control.instance.fetch('timeout', 2 * 60)
      
      @invalid_license = false
      
      @last_harvest_time = Time.now
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
        @agent_id = invoke_remote :start, @local_host, {
          :pid => $$, 
          :launch_time => @launch_time.to_f, 
          :agent_version => NewRelic::VERSION::STRING, 
          :environment => control.local_env.snapshot,
          :settings => control.settings }
        
        host = invoke_remote(:get_redirect_host) rescue nil
        
        @collector = control.server_from_host(host) if host        
            
        @report_period = invoke_remote :get_data_report_period, @agent_id
 
        control.log! "Connected to NewRelic Service at #{@collector}"
        log.debug "Agent ID = #{@agent_id}."
        
        # Ask the server for permission to send transaction samples.  determined by subscription license.
        @should_send_samples = invoke_remote :should_collect_samples, @agent_id
        
        if @should_send_samples
          sampling_rate = invoke_remote :sampling_rate, @agent_id if @random_sample
          @transaction_sampler.sampling_rate = sampling_rate
            
          log.info "Transaction sample rate: #{sampling_rate}"
        end
        
        # Ask for mermission to collect error data
        @should_send_errors = invoke_remote :should_collect_errors, @agent_id
        
        log.info "Transaction traces will be sent to the RPM service" if @use_transaction_sampler && @should_send_samples
        log.info "Errors will be sent to the RPM service" if @error_collector.enabled && @should_send_errors
        
        @connected = true
        
      rescue LicenseException => e
        control.log! e.message, :error
        control.log! "Visit NewRelic.com to obtain a valid license key, or to upgrade your account."
        @invalid_license = true
        return false
        
      rescue Timeout::Error, StandardError => e
        log.info "Unable to establish connection with New Relic RPM Service at #{control.server}"
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
          connect_retry_period, period_msg = 60, "1 minute"
        else 
          connect_retry_period, period_msg = 10*60, "10 minutes"
        end
        log.info "Will re-attempt in #{period_msg}" if period_msg
        retry
      end
    end
      
    def determine_host
      Socket.gethostname
    end
    
    def determine_home_directory
      control.root
    end
    
    def harvest_and_send_timeslice_data
      
      NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.harvest_busy
      
      now = Time.now
      
      # Fixme: remove the harvest thread tracking
      @harvest_thread ||= Thread.current
      
      if @harvest_thread != Thread.current
        log.error "Two harvest threads are running (current=#{Thread.current}, harvest=#{@harvest_thread}"
        @harvest_thread = Thread.current
      end
      
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
      @traces = @transaction_sampler.harvest(@traces, @slowest_transaction_threshold)
      
      unless @traces.empty?
        now = Time.now
        log.debug "Sending (#{@traces.length}) transaction traces"
        
        # take the traces and prepare them for sending across the wire.  This includes
        # gathering SQL explanations, stripping out stack traces, and normalizing SQL.
        # note that we explain only the sql statements whose segments' execution times exceed 
        # our threshold (to avoid unnecessary overhead of running explains on fast queries.)
        traces = @traces.collect {|trace| trace.prepare_to_send(:explain_sql => @explain_threshold, :record_sql => @record_sql, :keep_backtraces => true, :explain_enabled => @explain_enabled)} 
        
        invoke_remote :transaction_sample_data, @agent_id, traces
        
        log.debug "#{now}: sent slowest sample (#{@agent_id}) in #{Time.now - now} seconds"
      end
      
      # if we succeed sending this sample, then we don't need to keep the slowest sample
      # around - it has been sent already and we can collect the next one
      @traces = nil
      
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
      data = Marshal.dump(args)
      encoding = data.size > 2000 ? 'deflate' : 'identity' # don't compress small payloads
      post_data = encoding == 'deflate' ? Zlib::Deflate.deflate(data, Zlib::BEST_SPEED) : data
      http = control.http_connection(collector)
      
      uri = "/agent_listener/#{PROTOCOL_VERSION}/#{control.license_key}/#{method}"
      uri += "?run_id=#{@agent_id}" if @agent_id
      
      request = Net::HTTP::Post.new(uri, 'CONTENT-ENCODING' => encoding, 'ACCEPT-ENCODING' => 'gzip', 'HOST' => collector.name)
      request.content_type = "application/octet-stream"
      request.body = post_data
      
      log.debug "connect to #{collector}#{uri}"
      
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
      log.error "RPM forced this agent to disconnect (#{e.message})\n" \
                       "Restart this process to resume monitoring via rpm.newrelic.com."
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
      if @connected && !(control.server.name == "localhost" && control.dispatcher_instance_id == '3000')
        begin
          log.debug "Sending graceful shutdown message to #{control.server}"
          
          @request_timeout = 5
          
          log.debug "Sending RPM service agent run shutdown message"
          invoke_remote :shutdown, @agent_id, Time.now.to_f
          
          log.debug "Graceful shutdown complete"
          
        rescue Timeout::Error, StandardError 
        end
      else
        log.debug "Bypassing graceful shutdown - agent in development mode"
      end
    end
  end
  
end
