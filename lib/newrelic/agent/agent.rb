require 'net/https' 
require 'net/http'
require 'logger'
require 'singleton'
require 'zlib'

require 'newrelic/stats'
require 'newrelic/agent/worker_loop'

require 'newrelic/agent/stats_engine'
require 'newrelic/agent/transaction_sampler'

# if Mongrel isn't present, we still need a class declaration
module Mongrel
  class HttpServer; end
end

# same for Thin HTTP Server
module Thin
  class Server; end
end

# The NewRelic Agent collects performance data from rails applications in realtime as the
# application runs, and periodically sends that data to the NewRelic server.  
module NewRelic::Agent
  
  # an exception that is thrown by the server if the agent license is invalid
  class LicenseException < Exception; end
  
  # an exception that forces an agent to stop reporting until its mongrel is restarted
  class ForceDisconnectException < Exception; end
  
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
    def get_stats(metric_name)
      # unless metric_name =~ /Custom\// 
      #   raise Exception.new("Invalid Name for Application Custom Metric: #{metric_name}")
      # end
      agent.stats_engine.get_stats(metric_name, false)
    end
  end
  
  # Implementation defail for the NewRelic Agent
  class Agent
    # Specifies the version of the agent's communication protocol
    # with the NewRelic hosted site.
    #
    # VERSION HISTORY
    # 1: Private Beta, Jan 10, 2008.  Serialized Marshalled Objects.  Unsupported after 5/29/2008.
    # 2: Private Beta, March 15, 2008.  Compressed Serialzed Marshalled Objects (15-20x smaller)
    PROTOCOL_VERSION = 2
    
    include Singleton
    
    DEFAULT_HOST = 'localhost'
    DEFAULT_PORT = 3000
    
    attr_reader :stats_engine
    attr_reader :transaction_sampler
    attr_reader :worker_loop
    attr_reader :log
    attr_reader :license_key
    attr_reader :config
    attr_reader :remote_host
    attr_reader :remote_port
    attr_reader :local_port
    
    # Start up the agent, which will connect to the newrelic server and start 
    # reporting performance information.  Typically this is done from the
    # environment configuration file
    def start(config)
      if @started
        log! "Agent Started Already!"
        raise Exception.new("Duplicate attempt to start the NewRelic agent")
      end
      
      @config = config
      
      @local_port = determine_environment_and_port
      @local_host = determine_host
      
      setup_log
      
      @worker_loop = WorkerLoop.new(@log)
      @started = true
      
      @sample_threshold = (config['sample_threshold'] || 2).to_i
      @license_key = config.fetch('license_key', nil)
      
      @use_ssl = config.fetch('ssl', false)
      default_port = @use_ssl ? 443 : 80
      
      @remote_host = config.fetch('host', 'collector.newrelic.com')
      @remote_port = config.fetch('port', default_port)
      
      if config['enabled'] || config['developer']
        instrument_rails
        
        if config['enabled']
          # make sure the license key exists and is likely to be really a license key
          # by checking it's string length (license keys are 40 character strings.)
          unless @license_key && @license_key.length == 40
            log! "No license key found.  Please insert your license key into agent/newrelic.yml"
            return
          end

          load_samplers
          
          @worker_thread = Thread.new do 
            run_worker_loop
          end
        end
        
        # When the VM shuts down, attempt to send a message to the server that
        # this agent run is stopping, assuming it has successfully connected
        at_exit do
          @worker_thread.terminate if @worker_thread
          graceful_disconnect
        end
      end
    end
    
    private
    def initialize
      @connected = false
      @launch_time = Time.now
      
      @metric_ids = {}
      @environment = :unknown
      
      @stats_engine = StatsEngine.new
      @transaction_sampler = TransactionSampler.new(self)
    end
    
    def setup_log
      if @local_port
        log_file = "#{RAILS_ROOT}/log/newrelic_agent.#{@local_port}.log"
      else
        log_file = "#{RAILS_ROOT}/log/newrelic_agent.log"
      end
      
      @log = Logger.new log_file
      @log.level = Logger::INFO
      
      @stats_engine.log = @log
      
      # set the log level as specified in the config file
      case config.fetch("log_level","info").downcase
        when "debug": @log.level = Logger::DEBUG
        when "info": @log.level = Logger::INFO
        when "warn": @log.level = Logger::WARN
        when "error": @log.level = Logger::ERROR
        when "fatal": @log.level = Logger::FATAL
      else @log.level = Logger::INFO
      end
      
      log! "New Relic RPM Agent Initialized: pid = #{$$}"
      to_stderr "Agent Log is found in #{log_file}"
      log.info "Runtime environment: #{@environment.to_s.titleize}"
    end
    
    # Connect to the server, and run the worker loop forever
    def run_worker_loop
      # bail if the application is not running in a mongrel process unless
      # the user explicitly asks to monitor non-mongrel processes (assumed to 
      # be daemons) by setting 'monitor_daemons' to true in newrelic.yaml
      # attempt to connect to the server
      return unless should_run?
      
      until @connected
        should_retry = connect
        return unless should_retry
      end
      
      # determine the reporting period (server based)
      # note if the agent attempts to report more frequently than the specified
      # report data, then it will be ignored.
      report_period = invoke_remote :get_data_report_period, @agent_id
      log! "Reporting performance data every #{report_period} seconds"        
      @worker_loop.add_task(report_period) do 
        harvest_and_send_timeslice_data
      end
      
      if @should_send_samples
        @worker_loop.add_task(report_period) do 
          harvest_and_send_slowest_sample
        end
      end
      
      @worker_loop.run
    end
    
    # return true if the agent should run the worker loop.
    def should_run?
      @local_port || config['monitor_daemons'] || @environment == :thin
    end
    
    def connect
      @connect_retry_period ||= 5
      @connect_attempts ||= 0
      
      # wait a few seconds for the web server to boot
      sleep @connect_retry_period.to_i
      
      @agent_id = invoke_remote :launch, @local_host,
               @local_port, determine_home_directory, $$, @launch_time
      
      log! "Connected to NewRelic Service at #{@remote_host}:#{@remote_port}."
      log.debug "Agent ID = #{@agent_id}."
      
      # Ask the server for permission to send transaction samples.  determined by suvbscription license.
      @should_send_samples = invoke_remote :should_collect_samples, @agent_id
      
      @connected = true
      @last_harvest_time = Time.now
      return true
      
    rescue LicenseException => e
      log! e.message, :error
      log! "Visit NewRelic.com to obtain a valid license key, or to upgrade your account."
      log! "Turning New Relic Agent off."
      return false
      
    rescue Exception => e
      log.error "Error attempting to connect to New Relic RPM Service at #{@remote_host}:#{@remote_port}"
      log.error e.message
      log.debug e.backtrace.join("\n")
      
      # retry logic
      @connect_attempts += 1
      if @connect_attempts > 20
        @connect_retry_period, period_msg = 10.minutes, "10 minutes"
      elsif @connect_attempts > 10
        @connect_retry_period, period_msg = 1.minutes, "1 minute"
      elsif @connect_attempts > 5
        @connect_retry_period, period_msg = 30, nil
      else
        @connect_retry_period, period_msg = 5, nil
      end
      
      log.info "Will re-attempt in #{period_msg}" if period_msg
      return true
    end
    
    def load_samplers
      sampler_files = File.join(File.dirname(__FILE__), 'samplers', '*.rb')
      Dir.glob(sampler_files) do |file|
        begin
          require file
        rescue Exception => e
          log.error "Error loading sampler '#{file}': #{e}"
        end
      end
    end
    
    def determine_host
      Socket.gethostname
    end
    
    # determine the environment we are running in (one of :webrick,
    # :mongrel, :thin, or :unknown) and if the process is listening
    # on a port, return the port # that we are listening on.
    def determine_environment_and_port
      port = nil
      
      # OPTIONS is set by script/server 
      port = OPTIONS.fetch :port, DEFAULT_PORT
      @environment = :webrick
      
    rescue NameError
      # this case covers starting by mongrel_rails
      # TODO review this approach.  There should be only one http server
      # allocated in a given rails process...
      ObjectSpace.each_object(Mongrel::HttpServer) do |mongrel|
        port = mongrel.port
        @environment = :mongrel
      end
      
      # this case covers the thin web server
      # Same issue as above- we assume only one instance per process
      # NOTE if a thin server and a mongrel server were to coexist in a single
      # ruby process (no idea why that would ever happen) the thin server
      # would "win out" as the determined runtime environment
      ObjectSpace.each_object(Thin::Server) do |thin_server|
        @environment = :thin
        
        # TODO when thin uses UNIX domain sockets, we likely don't have a port
        # setting.  So therefore we need another way to uniquely define this
        # "instance", otherwise, a host running >1 thin instances will appear
        # as 1 agent to us, and we will have a license counting problem (as well
        # as a data granularity problem).
        port = thin_server.port
       
        if port.nil? && false     # TODO we need to make mods on the server to accept port as a string
          port = thin_server.socket
        end
        port
      end
      
    rescue NameError
      log.info "Could not determine port.  Likely running as a cgi"
      @environment = :unknown
      
    ensure
      return port
    end
    
    def determine_home_directory
      File.expand_path(RAILS_ROOT)
    end
    
    def instrument_rails
      Module.method_tracer_log = log
      
      # Instrumentation for the key code points inside rails for monitoring by NewRelic.
      # note this file is loaded only if the newrelic agent is enabled (through config/newrelic.yml)
      instrumentation_files = File.join(File.dirname(__FILE__), 'instrumentation', '*.rb')
      Dir.glob(instrumentation_files) do |file|
        begin
          require file
          log.info "Processed instrumentation file '#{file.split('/').last}'"
        rescue Exception => e
          log.error "Error loading instrumentation file '#{file}': #{e}"
          log.debug e.backtrace.join("\n")
        end
      end
    end
    
    @last_harvest_time = Time.now
    def harvest_and_send_timeslice_data
      now = Time.now
      @unsent_timeslice_data ||= {}
      @unsent_timeslice_data = @stats_engine.harvest_timeslice_data(@unsent_timeslice_data, @metric_ids)
      
      metric_ids = invoke_remote(:metric_data, @agent_id, 
              @last_harvest_time.to_f, 
              now.to_f, 
              @unsent_timeslice_data.values)
      @metric_ids.merge! metric_ids unless metric_ids.nil?
      
      log.debug "#{Time.now}: sent #{@unsent_timeslice_data.length} timeslices (#{@agent_id})"
      
      # if we successfully invoked this web service, then clear the unsent message cache.
      @unsent_timeslice_data.clear
      @last_harvest_time = Time.now
      
      # handle_messages 
      
      # note - exceptions are logged in invoke_remote.  If an exception is encountered here,
      # then the metric data is downsampled for another timeslices
    end
    
    def harvest_and_send_slowest_sample
      @slowest_sample = @transaction_sampler.harvest_slowest_sample(@slowest_sample)
      
      if @slowest_sample && @slowest_sample.duration > @sample_threshold
        log.debug "Sending Slowest Sample: #{@slowest_sample.params[:path]}, #{@slowest_sample.duration.to_ms} ms" if @slowest_sample
        
        # take the slowest sample, and prepare it for sending across the wire.  This includes
        # gathering SQL explanations, stripping out stack traces, and normalizing SQL.
        # note that we explain only the sql statements whose segments' execution times exceed 
        # our threshold (to avoid unnecessary overhead of running explains on fast queries.)
        sample = @slowest_sample.prepare_to_send(:explain_sql => 0.5)
        invoke_remote :transaction_sample_data, @agent_id, sample
      end
      
      # if we succeed sending this sample, then we don't need to keep the slowest sample
      # around - it has been sent already and we can collect the next one
      @slowest_sample = nil
      
      # note - exceptions are logged in invoke_remote.  If an exception is encountered here,
      # then the slowest sample of is determined of the entire period since the last
      # reported sample.
    end
    
    def handle_messages(messages)
      messages.each do |message|
        begin
          message = Marshal.load(message)
          message.execute(self)
          log.debug("Received Message: #{message.to_yaml}")
        rescue Exception => e
          log.error "Error handling message: #{e}"
          log.debug e.backtrace.join("\n")
        end
      end 
    end
    
    # send a message via post
    # As of Version 2, the agent-server protocol is:
    # params[:method] => method name(string)
    # params[:license_key] => license key(string)
    # params[:version] => protocol version(integer, 2 or higher)
    def invoke_remote(method, *args)
      # we currently optimize for CPU here since we get roughly a 10x reduction in
      # message size with this, and CPU overhead is at a premium.  If we wanted
      # to go for higher compression instead, we could use Zlib::BEST_COMPRESSION and 
      # pay a little more CPU.
      post_data = CGI::escape(Zlib::Deflate.deflate(Marshal.dump(args), Zlib::BEST_SPEED))
      
      request = Net::HTTP.new(@remote_host, @remote_port.to_i) 
      if @use_ssl
        request.use_ssl = true 
        request.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      
      # FIXME for the life of me I cant find the API that assembles query parameters into a 
      # URI, so I have to hard code it here. Ugly to say the least.
      uri = "/agent_listener/invoke_raw_method?method=#{method}&license_key=#{license_key}&protocol_version=#{PROTOCOL_VERSION}"
      response = request.start do |http|
        http.post(uri, post_data) 
      end
      
      if response.is_a? Net::HTTPSuccess
        return_value = Marshal.load(Zlib::Inflate.inflate(CGI::unescape(response.body)))
        if return_value.is_a? Exception
          raise return_value
        else
          return return_value
        end
      else
        raise Exception.new("#{response.code}: #{response.message}")
      end 
    rescue ForceDisconnectException => e
      log! "RPM forced this agent to disconnect", :error
      log! e.message, :error
      log! "Restart this process to resume RPM's agent communication with NewRelic.com"
      # when a disconnect is requested, stop the current thread, which is the worker thread that 
      # gathers data and talks to the server. 
      @connected = false
      Thread.exit

    rescue Exception => e
      log.error("Error communicating with RPM Service at #{@remote_host}:#{remote_port}: #{e}")
      log.debug(e.backtrace.join("\n"))
      raise e
    end
    
    # send the given message to STDERR as well as the agent log, so that it shows
    # up in the console.  This should be used for important informational messages at boot
    def log!(msg, level = :info)
      to_stderr msg
      log.send level, msg if log
    end
    
    def to_stderr(msg)
      # only log to stderr when we are running as a mongrel process, so it doesn't
      # muck with daemons and the like.
      unless @environment == :unknown
        STDERR.puts "** [NewRelic] " + msg 
      end
    end
    
    def graceful_disconnect
      if @connected
        begin
          log.debug "Sending graceful shutdown message to #{remote_host}:#{remote_port}"
          invoke_remote :shutdown, @agent_id, Time.now 
          log.debug "Shutdown Complete"
        rescue Exception => e
          log.warn "Error sending shutdown message to #{remote_host}:#{remote_port}:"
          log.warn e
          log.debug e.backtrace.join("\n")
        end
      end
    end
  end
  
end
