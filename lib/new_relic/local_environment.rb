# An instance of LocalEnvironment will provide the environment name
# and locally unique identifier for this agent's host.
# If the environment can't be determined, it will be set to
# :unknown and identifier will have nil
module NewRelic 
  class LocalEnvironment
    
    attr_reader :environment, :identifier
    
    # determine the environment we are running in (one of :webrick,
    # :mongrel, :thin, or :unknown) and if the process is listening
    # on a port, use the port # that we are listening on. 
    def initialize
      # Note: log won't be available yet.
      @identifier = nil
      @environment = :unknown
      environments = %w[merb jruby webrick mongrel thin litespeed passenger daemon]
      while environments.any? && @identifier.nil?
        send 'check_for_'+(environments.shift)
      end
    end
    def to_s
      "LocalEnvironment[#{environment}:#{identifier}]"
    end
    def check_for_merb
      if config.app == :merb
        @identifier = 'merb'
      end
    end
    def check_for_webrick
      if defined?(OPTIONS) && OPTIONS.respond_to?(:fetch) 
        # OPTIONS is set by script/server 
        @identifier = OPTIONS.fetch(:port)
        @environment = :webrick
      end
    end
    
    # this case covers starting by mongrel_rails
    def check_for_mongrel
      if defined? Mongrel::HttpServer
        ObjectSpace.each_object(Mongrel::HttpServer) do |mongrel|
          next if not mongrel.respond_to? :port
          @environment = :mongrel
          @identifier = mongrel.port
        end
      end
    end
    
    def check_for_thin
      if defined? Thin::Server
        # This case covers the thin web server
        # Same issue as above- we assume only one instance per process
        ObjectSpace.each_object(Thin::Server) do |thin_server|
          @environment = :thin
          backend = thin_server.backend
          # We need a way to uniquely identify and distinguish agents.  The port
          # works for this.  When using sockets, use the socket file name.
          if backend.respond_to? :port
            @identifier = backend.port
          elsif backend.respond_to? :socket
            @identifier = backend.socket
          else
            raise "Unknown thin backend: #{backend}"
          end
        end # each thin instance
      end
    end
    
    def check_for_jruby
      if RUBY_PLATFORM =~ /java/
        # Check for JRuby environment.  Not sure how this works in different appservers
        require 'java'
        require 'jruby'
        @environment = :jruby
        @identifier = 'jruby'
        @identifier += ":#{config['app_name']}" if config['app_name']
      end
    end
    
    def check_for_litespeed
      if caller.pop =~ /fcgi-bin\/RailsRunner\.rb/
        @environment = :litespeed
        @identifier = 'litespeed'
        @identifier += ":#{config['app_name']}" if config['app_name']
      end
    end
    
    def check_for_passenger
      if defined? Passenger::AbstractServer || defined? IN_PHUSION_PASSENGER 
        @environment = :passenger
        @identifier = 'passenger'
        @identifier += ":#{config['app_name']}" if config['app_name']
      end
    end
    
    def check_for_daemon
      if config['monitor_daemons']
        @environment = :daemon
        # return the base part of the file name
        @identifier = File.basename($0).split(".").first
      end
    end
    private 
    def config
      NewRelic::Config.instance
    end
  end
end
