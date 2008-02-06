require 'net/http'
require 'logger'
require 'singleton'

require 'newrelic/stats'
require 'newrelic/agent/worker_loop'
require 'newrelic/agent_messages'

require 'newrelic/agent/stats_engine'
require 'newrelic/agent/transaction_sampler'

# if Mongrel isn't present, we still need a class declaration
module Mongrel
  class HttpServer; end
end

# The NewRelic Agent collects performance data from rails applications in realtime as the
# application runs, and periodically sends that data to the NewRelic server.  
module NewRelic::Agent
  
  # an exception that is thrown by the server if the agent license is invalid
  class LicenseException < Exception; end
  
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
    PROTOCOL_VERSION = 1
    
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
    
    # Start up the agent, which will connect to the newrelic server and start 
    # reporting performance information.  Typically this is done from the
    # environment configuration file
    def start(config)
      if @started
        log.error "Agent Started Already!"
        raise Exception.new("Duplicate attempt to start the NewRelic agent")
      end
      
      @config = config
      
      # set the log level as specified in the config file
      case config.fetch("log_level","info").downcase
        when "debug": @log.level = Logger::DEBUG
        when "info": @log.level = Logger::INFO
        when "warn": @log.level = Logger::WARN
        when "error": @log.level = Logger::ERROR
        when "fatal": @log.level = Logger::FATAL
        else @log.level = Logger::INFO
      end
    
      @started = true
      
      @license_key = config.fetch('license_key', nil)
      unless @license_key
        log! "No license key found.  Please insert your license key into agent/new_relic.yml"
        return
      end
      
      @remote_host = config.fetch('host', 'rpm.newrelic.com')
      @remote_port = config.fetch('port', '80')

      if config['enabled']
        load_samplers
      
        @worker_thread = Thread.new do 
          run_worker_loop
        end
      
        # When the VM shuts down, attempt to send a message to the server that
        # this agent run is stopping, assuming it has successfully connected
        at_exit do
          invoke_remote :shutdown, @agent_id, Time.now if @connected
        end
      end
    end
  
    private
      def initialize
        @my_port = determine_port
        @my_host = determine_host
        
        @connected = false
        @launch_time = Time.now
       
        @worker_loop = WorkerLoop.new(@log)
        
        @metric_ids = {}
        
        @stats_engine = StatsEngine.new(@log)
        @transaction_sampler = TransactionSampler.new(self)
        
        if @my_port
          log_file = "log/newrelic_agent.#{@my_port}.log"
        else
          log_file = "log/newrelic_agent.log"
        end
        
        @log = Logger.new log_file
        @log.level = Logger::INFO
      
        log! "New Relic RPM Agent Initialized: pid = #{$$}"
        to_stderr "Agent Log is found in #{log_file}"
      end
      
      # Connect to the server, and run the worker loop forever
      def run_worker_loop
        # bail if the application is not running in a mongrel process (ie, it's 
        # a rake task, or a batch job, or perhaps it's running in an fcgi environment
        # which is not yet supportedd)
        # attempt to connect to the server
        return unless @my_port || @config['monitor_daemons']
        
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

        @worker_loop.run
      end
    
      def connect
        @connect_retry_period ||= 5
        @connect_attempts ||= 0
        
        # wait a few seconds for the web server to boot
        sleep @connect_retry_period.to_i
        
        @agent_id = invoke_remote :launch, @my_host,
          @my_port, determine_home_directory, $$, @launch_time
        
        log! "Connected to NewRelic Service at #{@remote_host}:#{@remote_port}."
        log.debug "Agent ID = #{@agent_id}."

        @connected = true
        @last_harvest_time = Time.now
        return true
        
      rescue LicenseException => e
        log! e.message, :error
        log! "Visit NewRelic.com to obtain a valid license key, or contact NewRelic support to recover your license key"
        log! "Turning New Relic Agent off.  Restart your Mongrel after putting the correct license key in config/newrelic.yml"
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
      
      def determine_port
        port = nil
        
        # OPTIONS is set by script/server 
        port = OPTIONS.fetch :port, DEFAULT_PORT
      rescue NameError
        # this case covers starting by mongrel_rails
        # TODO review this approach.  There should be only one http server
        # allocated in a given rails process...
        ObjectSpace.each_object(Mongrel::HttpServer) do |mongrel|
          port = mongrel.port
        end
      rescue NameError
        log.info "Could not determine port.  Likely running as a cgi"
      ensure
        return port
      end
      
      def determine_home_directory
        File.expand_path(RAILS_ROOT)
      end
      
      @last_harvest_time = Time.now
      def harvest_and_send_timeslice_data
        now = Time.now
        @unsent_timeslice_data ||= {}
        @unsent_timeslice_data = @stats_engine.harvest_timeslice_data(@unsent_timeslice_data, @metric_ids)
        
        metric_ids = invoke_remote :metric_data, @agent_id, 
                  @last_harvest_time.to_f, 
                  now.to_f, 
                  @unsent_timeslice_data.values
        @metric_ids.merge! metric_ids unless metric_ids.nil?
        
        log.debug "#{Time.now}: sent #{@unsent_timeslice_data.length} timeslices (#{@agent_id})"

        # if we successfully invoked this web service, then clear the unsent message cache.
        @unsent_timeslice_data.clear
        @last_harvest_time = Time.now
        
        # handle_messages 
        
        # note - exceptions are logged in invoke_remote.  If an exception is encountered here,
        # then the metric data is downsampled for another timeslices
      end

      def harvest_and_send_sample_data
        @unsent_samples ||= []
        @unsent_samples = @transaction_sampler.harvest_samples(@unsent_samples)
        
        # limit the sample data to 100 elements, to prevent server flooding
        @unsent_samples = @unsent_samples[0..100] if @unsent_samples.length > 100
        
        # avoid the webservice call if there is no data to send
        if @unsent_samples.length > 0
          sample_data = []
          @unsent_samples.each do |sample|
            sample_data.push Marshal.dump(sample)
          end
          
          messages = invoke_remote :transaction_sample_data, @agent_id, sample_data
        
          # if we successfully invoked the web service, then clear the unsent sample cache
          @unsent_samples.clear
          handle_messages messages
        end
      end

      def ping
        messages = @agent_listener_service.ping @agent_id
        handle_messages messages
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
      def invoke_remote(method, *args)
        post_data = [license_key, method, PROTOCOL_VERSION, args]
        post_data = CGI::escape(Marshal.dump(post_data))

        res = Net::HTTP.start(@remote_host, @remote_port) do |http|
          http.post('/agent_listener/invoke_raw_method', post_data) 
        end

        return_value = Marshal.load(CGI::unescape(res.body))
      rescue Exception => e
        log.error("Error communicating with RPM Service at #{@remote_port}:#{remote_port}: #{e}")
        log.debug(e.backtrace.join("\n"))
        return_value = e
      ensure
        if return_value.is_a? Exception
          raise return_value
        else
          return return_value
        end
      end
      
      # send the given message to STDERR as well as the agent log, so that it shows
      # up in the console.  This should be used for important informational messages at boot
      def log!(msg, level = :info)
        to_stderr msg
        log.send level, msg
      end
      
      def to_stderr(msg)
        STDERR.puts "** [NewRelic] " + msg
      end
  end

end

