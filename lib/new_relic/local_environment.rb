# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'set'
require 'new_relic/version'

module NewRelic
  # An instance of LocalEnvironment is responsible for determining
  # three things:
  #
  # * Dispatcher - A supported dispatcher, or nil (:mongrel, :thin, :passenger, :webrick, etc)
  # * Dispatcher Instance ID, which distinguishes agents on a single host from each other
  #
  # If the environment can't be determined, it will be set to
  # nil and dispatcher_instance_id will have nil.
  #
  # NewRelic::LocalEnvironment should be accessed through NewRelic::Control#env (via the NewRelic::Control singleton).
  class LocalEnvironment
    # mongrel, thin, webrick, or possibly nil
    def discovered_dispatcher
      discover_dispatcher unless @discovered_dispatcher
      @discovered_dispatcher
    end

    # used to distinguish instances of a dispatcher from each other, may be nil
    attr_writer :dispatcher_instance_id
    # The number of cpus, if detected, or nil - many platforms do not
    # support this :(
    attr_reader :processors

    def initialize
      # Extend self with any any submodules of LocalEnvironment.  These can override
      # the discover methods to discover new framworks and dispatchers.
      NewRelic::LocalEnvironment.constants.each do | const |
        mod = NewRelic::LocalEnvironment.const_get const
        self.extend mod if mod.instance_of? Module
      end

      discover_dispatcher
      @gems = Set.new
      @plugins = Set.new
      @config = Hash.new
    end


    # An instance id pulled from either @dispatcher_instance_id or by
    # splitting out the first part of the running file
    def dispatcher_instance_id
      if @dispatcher_instance_id.nil?
        if @discovered_dispatcher.nil?
          @dispatcher_instance_id = File.basename($0).split(".").first
        end
      end
      @dispatcher_instance_id
    end

    # it's a working jruby if it has the runtime method, and object
    # space is enabled
    def working_jruby?
      !(defined?(::JRuby) && JRuby.respond_to?(:runtime) && !JRuby.runtime.is_object_space_enabled)
    end

    # Runs through all the objects in ObjectSpace to find the first one that
    # match the provided class
    def find_class_in_object_space(klass)
      ObjectSpace.each_object(klass) do |x|
        return x
      end
      return nil
    end

    # Sets the @mongrel instance variable if we can find a Mongrel::HttpServer
    def mongrel
      return @mongrel if @mongrel
      if defined?(::Mongrel) && defined?(::Mongrel::HttpServer) && working_jruby?
        @mongrel = find_class_in_object_space(::Mongrel::HttpServer)
      end
      @mongrel
    end

    private

    # Although you can override the dispatcher with NEWRELIC_DISPATCHER this
    # is not advisable since it implies certain api's being available.
    def discover_dispatcher
      dispatchers = %w[passenger torquebox trinidad glassfish resque sidekiq thin mongrel litespeed webrick fastcgi rainbows unicorn]
      while dispatchers.any? && @discovered_dispatcher.nil?
        send 'check_for_'+(dispatchers.shift)
      end
    end

    def check_for_torquebox
      return unless defined?(::JRuby) &&
         ( org.torquebox::TorqueBox rescue nil)
      @discovered_dispatcher = :torquebox
    end

    def check_for_glassfish
      return unless defined?(::JRuby) &&
        (((com.sun.grizzly.jruby.rack.DefaultRackApplicationFactory rescue nil) &&
          defined?(com::sun::grizzly::jruby::rack::DefaultRackApplicationFactory)) ||
         (jruby_rack? && defined?(::GlassFish::Server)))
      @discovered_dispatcher = :glassfish
    end

    def check_for_trinidad
      return unless defined?(::JRuby) && jruby_rack? && defined?(::Trinidad::Server)
      @discovered_dispatcher = :trinidad
    end

    def jruby_rack?
      ((org.jruby.rack.DefaultRackApplicationFactory rescue nil) &&
       defined?(org::jruby::rack::DefaultRackApplicationFactory))
    end

    def check_for_webrick
      return unless defined?(::WEBrick) && defined?(::WEBrick::VERSION)
      @discovered_dispatcher = :webrick
      if defined?(::OPTIONS) && OPTIONS.respond_to?(:fetch)
        # OPTIONS is set by script/server
        @dispatcher_instance_id = OPTIONS.fetch(:port)
      end
      @dispatcher_instance_id = default_port unless @dispatcher_instance_id
    end

    def check_for_fastcgi
      return unless defined?(::FCGI)
      @discovered_dispatcher = :fastcgi
    end

    # this case covers starting by mongrel_rails
    def check_for_mongrel
      return unless defined?(::Mongrel) && defined?(::Mongrel::HttpServer)
      @discovered_dispatcher = :mongrel

      # Get the port from the server if it's started

      if mongrel && mongrel.respond_to?(:port)
        @dispatcher_instance_id = mongrel.port.to_s
      end

      # Get the port from the configurator if one was created
      if @dispatcher_instance_id.nil? && defined?(::Mongrel::Configurator)
        ObjectSpace.each_object(Mongrel::Configurator) do |mongrel|
          @dispatcher_instance_id = mongrel.defaults[:port] && mongrel.defaults[:port].to_s
        end unless defined?(::JRuby) && !JRuby.runtime.is_object_space_enabled
      end

      # Still can't find the port.  Let's look at ARGV to fall back
      @dispatcher_instance_id = default_port if @dispatcher_instance_id.nil?
    end

    def check_for_unicorn
      if (defined?(::Unicorn) && defined?(::Unicorn::HttpServer)) && working_jruby?
        v = find_class_in_object_space(::Unicorn::HttpServer)
        @discovered_dispatcher = :unicorn if v 
      end
    end

    def check_for_rainbows
      if (defined?(::Rainbows) && defined?(::Rainbows::HttpServer)) && working_jruby?
        v = find_class_in_object_space(::Rainbows::HttpServer)
        @discovered_dispatcher = :rainbows if v
      end
    end

    def check_for_resque
      using_resque = (
        defined?(::Resque) &&
        (ENV['QUEUE'] || ENV['QUEUES']) &&
        (File.basename($0) == 'rake' && ARGV.include?('resque:work'))
      )
      @discovered_dispatcher = :resque if using_resque
    end

    def check_for_sidekiq
      if defined?(::Sidekiq) && File.basename($0) == 'sidekiq'
        @discovered_dispatcher = :sidekiq
      end
    end

    def check_for_thin
      if defined?(::Thin) && defined?(::Thin::Server)
        # This case covers the thin web dispatcher
        # Same issue as above- we assume only one instance per process
        ObjectSpace.each_object(Thin::Server) do |thin_dispatcher|
          @discovered_dispatcher = :thin
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
      if defined?(::Thin) && defined?(::Thin::VERSION) && !@discovered_dispatcher
        @discovered_dispatcher = :thin
        @dispatcher_instance_id = default_port
      end
    end

    def check_for_litespeed
      if caller.pop =~ /fcgi-bin\/RailsRunner\.rb/
        @discovered_dispatcher = :litespeed
      end
    end

    def check_for_passenger
      if defined?(::PhusionPassenger)
        @discovered_dispatcher = :passenger
      end
    end


    def default_port
      require 'optparse'
      # If nothing else is found, use the 3000 default
      default_port = 3000
      OptionParser.new do |opts|
        opts.on("-p", "--port=port", String) { | p | default_port = p }
        opts.parse(ARGV.clone) rescue nil
      end
      default_port
    end

    public
    # outputs a human-readable description
    def to_s
      s = "LocalEnvironment["
      s << ";dispatcher=#{@discovered_dispatcher}" if @discovered_dispatcher
      s << ";instance=#{@dispatcher_instance_id}" if @dispatcher_instance_id
      s << "]"
    end

  end
end
