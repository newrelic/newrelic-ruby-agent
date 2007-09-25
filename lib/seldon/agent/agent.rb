require 'logger'

# from Common
require 'seldon/stats'
require 'seldon/agent_messages'
require 'seldon/agent_listener_api'

# from Agent
require 'seldon/agent/stats_engine'
require 'seldon/agent/transaction_sampler'
require 'seldon/agent/worker_loop'

# if Mongrel isn't present, we still need a class declaration
module Mongrel
  class HttpServer; end
end

module Seldon::Agent
  # add some convenience methods for easy access to the Agent singleton.
  # the following static methods all point to the same Agent instance:
  #
  # Seldon::Agent.agent
  # Seldon::Agent.instance
  # Seldon::Agent::Agent.instance
  class << self
    def agent
      Seldon::Agent::Agent.instance
    end
    
    alias instance agent
  end
  
  class Agent
    include Singleton
    
    DEFAULT_HOST = 'localhost'
    DEFAULT_PORT = 3000
    
    attr_reader :stats_engine
    attr_reader :transaction_sampler
    attr_reader :worker_loop
    attr_reader :log
    attr_reader :host
    attr_reader :port
    
    class << self
      def in_rails_environment?
        # FIXME there must be a better way to determine this
        OPTIONS.fetch :port
        true
      rescue Exception => e
        false
      end
    end
    
    # Start up the agent, which will connect to the seldon server and start 
    # reporting performance information.  Typically this is done from the
    # environment configuration file
    def start(config)
      if @started
        log.error "Agent Started Already!"
        raise Exception.new("Duplicate attempt to start the Seldon agent")
      end
      
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
      
      @host = config.fetch('host', 'localhost')
      @port = config.fetch('port', '3000')
      
      # add tasks to the worker loop.
      # TODO figure out how we configure reporting frequency.  Should be Server based to 
      # prevent hackers from flooding the server with metric data
      @worker_loop.add_task(15.0) do 
        harvest_and_send_timeslice_data
      end
      @worker_loop.add_task(5.0) do
        harvest_and_send_sample_data
      end
      @worker_loop.add_task(5.0) do
        ping
      end
      
      @worker_thread = Thread.new do 
        run_worker_loop
      end
    end
  
    private
      def initialize
        @log = Logger.new "log/seldon_agent.#{determine_port}.log"
        @log.level = Logger::DEBUG
        
        @connected = false
        @launch_time = Time.now
        
        @host = DEFAULT_HOST
        @port = DEFAULT_PORT
       
        @worker_loop = WorkerLoop.new(@log)
        
        @stats_engine = StatsEngine.new(@log)
        @transaction_sampler = TransactionSampler.new(self)
        
        log.info "\n\nSeldon Agent Initialized"
      end
      
      def connect
        begin
          # wait a few seconds for the web server to boot
          sleep 5
          
          # TODO make this configurable
          url = "http://#{host}:#{port}/agent_listener/api"
          
          @agent_listener_service = ActionWebService::Client::XmlRpc.new(
                Seldon::AgentListenerAPI, url)
          
          @agent_id = @agent_listener_service.launch determine_host, 
                determine_port, $$, @launch_time
          log.info "Connecting to Seldon Service at #{url}.  Agent ID = #{@agent_id}."
          
          @connected = true
          @last_harvest_time = Time.now
        rescue Exception
          log.error "error attempting to connect: #{$!}"
          log.error $@
        end
      end
    
      # this loop will run forever on its own thread, reporting data to the 
      # server
      def run_worker_loop
        # attempt to connect to the server
        until @connected
          connect
        end
        
        @worker_loop.run
      end
    
      def determine_host
        Socket.gethostname
      end
      
      def determine_port
        port = DEFAULT_PORT
        
        # OPTIONS is set by script/server
        port = OPTIONS.fetch :port, DEFAULT_PORT
      rescue NameError => e
        # this case covers starting by mongrel_rails
        # TODO review this approach.  There should be only one http server
        # allocated in a given rails process...
        ObjectSpace.each_object(Mongrel::HttpServer) do |mongrel|
          port = mongrel.port
        end
      rescue NameError => e
        log.error "COULD NOT DETERMINE PORT! "
      ensure
        return port
      end
      
      @last_harvest_time = Time.now
      def harvest_and_send_timeslice_data
        now = Time.now
        @unsent_timeslice_data ||= {}
        @unsent_timeslice_data = @stats_engine.harvest_timeslice_data(@unsent_timeslice_data)
        messages = @agent_listener_service.metric_data @agent_id, 
                  @last_harvest_time.to_f, 
                  now.to_f, 
                  @unsent_timeslice_data.values

        # if we successfully invoked this web service, then clear the unsent message cache.
        @unsent_timeslice_data.clear
        @last_harvest_time = Time.now
        
        handle_messages messages
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
          
          messages = @agent_listener_service.transaction_sample_data @agent_id, sample_data
        
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
  end

end

# sampler for CPU Time
module Seldon::Agent
  class CPUSampler
    def initialize
      t = Process.times
      @last_utime = t.utime
      @last_stime = t.stime
  
      agent = Seldon::Agent.instance
  
      agent.stats_engine.add_sampled_metric("CPU/User Time") do | stats |
        utime = Process.times.utime
        stats.record_data_point utime - @last_utime
        @last_utime = utime
      end
  
      agent.stats_engine.add_sampled_metric("CPU/System Time") do | stats |
        stime = Process.times.stime
        stats.record_data_point stime - @last_stime
        @last_stime = stime
      end
    end
  end
end

Seldon::Agent::CPUSampler.new