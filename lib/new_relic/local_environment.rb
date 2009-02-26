# An instance of LocalEnvironment will provide the environment name
# and locally unique dispatcher_instance_id for this agent's host.
# If the environment can't be determined, it will be set to
# nil and dispatcher_instance_id will have nil
module NewRelic 
  class LocalEnvironment

    attr_accessor :dispatcher # mongrel, thin, webrick, or possibly nil
    attr_accessor :dispatcher_instance_id # used to distinguish instances of a dispatcher from each other, may be nil
    attr_accessor :framework # rails, merb, :ruby, :daemon, test
    alias environment dispatcher
    def initialize
      discover_framework
      discover_dispatcher
    end
    
    def dispatcher_instance_id
      if @dispatcher_instance_id.nil?
        if @dispatcher
          @dispatcher_instance_id = @dispatcher.to_s
        else
          @dispatcher_instance_id = File.basename($0).split(".").first
        end
        @dispatcher_instance_id += ":#{config['app_name']}" if config['app_name']
      end
      @dispatcher_instance_id
    end
    private
    
    def discover_dispatcher
      dispatchers = %w[webrick mongrel thin litespeed passenger]
      while dispatchers.any? && @dispatcher.nil?
        send 'check_for_'+(dispatchers.shift)
      end
    end
    
    def discover_framework
      
      @framework = case
        when ENV['NEWRELIC_APPLICATION'] then ENV['NEWRELIC_APPLICATION'].to_sym 
        when defined? NewRelic::TEST then :test
        when defined? Merb::Plugins then :merb
        when defined? Rails then :rails
      else :ruby
      end      
    end

    private 

    def check_for_webrick
      if defined?(OPTIONS) && OPTIONS.respond_to?(:fetch) 
        # OPTIONS is set by script/dispatcher 
        @dispatcher_instance_id = OPTIONS.fetch(:port)
        @dispatcher = :webrick
      end
    end
    
    # this case covers starting by mongrel_rails
    def check_for_mongrel
      if defined? Mongrel::HttpServer
        ObjectSpace.each_object(Mongrel::HttpServer) do |mongrel|
          next if not mongrel.respond_to? :port
          @dispatcher = :mongrel
          @dispatcher_instance_id = mongrel.port
        end
      end
    end
    
    def check_for_thin
      if defined? Thin::Server
        # This case covers the thin web dispatcher
        # Same issue as above- we assume only one instance per process
        ObjectSpace.each_object(Thin::Server) do |thin_dispatcher|
          @dispatcher = :thin
          backend = thin_dispatcher.backend
          # We need a way to uniquely identify and distinguish agents.  The port
          # works for this.  When using sockets, use the socket file name.
          if backend.respond_to? :port
            @dispatcher_instance_id = backend.port
          elsif backend.respond_to? :socket
            @dispatcher_instance_id = backend.socket
          else
            raise "Unknown thin backend: #{backend}"
          end
        end # each thin instance
      end
    end
    
    def check_for_litespeed
      if caller.pop =~ /fcgi-bin\/RailsRunner\.rb/
        @dispatcher = :litespeed
      end
    end
    
    def check_for_passenger
      if defined?(Passenger::AbstractServer) || defined?(IN_PHUSION_PASSENGER) 
        @dispatcher = :passenger
      end
    end

    public 
    def to_s
      s = "LocalEnvironment["
      s << @framework.to_s
      s << ";dispatcher=#{@dispatcher}" if @dispatcher
      s << ";instance=#{@dispatcher_instance_id}" if @dispatcher_instance_id
      s << "]"
    end
    def gather_info
      i = []
      i << [ 'framework', @framework.to_s]
      i << [ 'dispatcher', @dispatcher.to_s]
      i << [ 'dispatcher_instance_id', @dispatcher_instance_id] if @dispatcher_instance_id
      i
    end
  end
end
