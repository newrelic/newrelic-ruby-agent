# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'set'
require 'new_relic/version'

module NewRelic
  # An instance of LocalEnvironment is responsible for determining the 'dispatcher'
  # in use by the current process.
  #
  # A dispatcher might be a recognized web server such as unicorn or passenger,
  # a background job processor such as resque or sidekiq, or nil for unknown.
  #
  # If the environment can't be determined, it will be set to nil.
  #
  # NewRelic::LocalEnvironment should be accessed through NewRelic::Control#env (via the NewRelic::Control singleton).
  class LocalEnvironment
    def discovered_dispatcher
      discover_dispatcher unless @discovered_dispatcher
      @discovered_dispatcher
    end

    def initialize
      # Extend self with any any submodules of LocalEnvironment.  These can override
      # the discover methods to discover new framworks and dispatchers.
      NewRelic::LocalEnvironment.constants.each do | const |
        mod = NewRelic::LocalEnvironment.const_get const
        self.extend mod if mod.instance_of? Module
      end

      discover_dispatcher
    end

    # Runs through all the objects in ObjectSpace to find the first one that
    # match the provided class
    def find_class_in_object_space(klass)
      if NewRelic::LanguageSupport.object_space_usable?
        ObjectSpace.each_object(klass) do |x|
          return x
        end
      end
      return nil
    end

    # Sets the @mongrel instance variable if we can find a Mongrel::HttpServer
    def mongrel
      return @mongrel if @looked_for_mongrel
      @looked_for_mongrel = true
      if defined?(::Mongrel) && defined?(::Mongrel::HttpServer)
        @mongrel = find_class_in_object_space(::Mongrel::HttpServer)
      end
      @mongrel
    end

    # Setter for testing
    def mongrel=(m)
      @looked_for_mongrel = true
      @mongrel = m
    end

    private

    # Although you can override the dispatcher with NEWRELIC_DISPATCHER this
    # is not advisable since it implies certain api's being available.
    def discover_dispatcher
      dispatchers = %w[passenger torquebox trinidad glassfish resque sidekiq delayed_job thin mongrel litespeed webrick fastcgi rainbows unicorn]
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
      defined?(JRuby::Rack::VERSION)
    end

    def check_for_webrick
      return unless defined?(::WEBrick) && defined?(::WEBrick::VERSION)
      @discovered_dispatcher = :webrick
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
      end

      # Might not have server yet, so allow one more check later on first request
      @looked_for_mongrel = false
    end

    def check_for_unicorn
      if (defined?(::Unicorn) && defined?(::Unicorn::HttpServer)) && NewRelic::LanguageSupport.object_space_usable?
        v = find_class_in_object_space(::Unicorn::HttpServer)
        @discovered_dispatcher = :unicorn if v
      end
    end

    def check_for_rainbows
      if (defined?(::Rainbows) && defined?(::Rainbows::HttpServer)) && NewRelic::LanguageSupport.object_space_usable?
        v = find_class_in_object_space(::Rainbows::HttpServer)
        @discovered_dispatcher = :rainbows if v
      end
    end

    def check_for_delayed_job
      if $0 =~ /delayed_job$/ || (File.basename($0) == 'rake' && ARGV.include?('jobs:work'))
        @discovered_dispatcher = :delayed_job
      end
    end

    def check_for_resque
      using_resque = (
        defined?(::Resque) &&
        (ENV['QUEUE'] || ENV['QUEUES']) &&
        (File.basename($0) == 'rake' && ARGV.include?('resque:work'))
      ) || (
        defined?(::Resque::Pool) &&
        (File.basename($0) == 'resque-pool')
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
        # If ObjectSpace is available, use it to search for a Thin::Server
        # instance. Otherwise, just the presence of the constant is sufficient.
        if NewRelic::LanguageSupport.object_space_usable?
          ObjectSpace.each_object(Thin::Server) do |thin_dispatcher|
            @discovered_dispatcher = :thin
          end
        else
          @discovered_dispatcher = :thin
        end
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

    public
    # outputs a human-readable description
    def to_s
      s = "LocalEnvironment["
      s << ";dispatcher=#{@discovered_dispatcher}" if @discovered_dispatcher
      s << "]"
    end

  end
end
