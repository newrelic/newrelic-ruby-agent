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

    # Add the given key/value pair to the app environment
    # settings.  Must pass either a value or a block.  Block
    # is called to get the value and any raised errors are
    # silently ignored.
    def append_environment_value(name, value = nil)
      value = yield if block_given?
      @config[name] = value if value
    rescue => e
      Agent.logger.error e
    end
    
    # yields to the block and appends the returned value to the list
    # of gems - this catches errors that might be raised in the block
    def append_gem_list
      @gems += yield
    rescue => e
      Agent.logger.error e
    end
    
    # yields to the block and appends the returned value to the list
    # of plugins - this catches errors that might be raised in the block
    def append_plugin_list
      @plugins += yield
    rescue => e
      Agent.logger.error e
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
    
    # Interrogates some common ruby constants for useful information
    # about what kind of ruby environment the agent is running in
    def gather_ruby_info
      append_environment_value('Ruby version'){ RUBY_VERSION }
      append_environment_value('Ruby description'){ RUBY_DESCRIPTION } if defined? ::RUBY_DESCRIPTION
      append_environment_value('Ruby platform') { RUBY_PLATFORM }
      append_environment_value('Ruby patchlevel') { RUBY_PATCHLEVEL }
      # room here for other ruby implementations, when.
      if defined? ::JRUBY_VERSION
        gather_jruby_info
      end
    end
    
    # like gather_ruby_info but for the special case of JRuby
    def gather_jruby_info
      append_environment_value('JRuby version') { JRUBY_VERSION }
      append_environment_value('Java VM version') { ENV_JAVA['java.vm.version']}
    end

    # See what the number of cpus is, works only on some linux variants
    def gather_cpu_info(proc_file='/proc/cpuinfo')
      return unless File.readable? proc_file
      @processors = append_environment_value('Processors') do
        cpuinfo = ''
        File.open(proc_file) do |f|
          loop do
            begin
              cpuinfo << f.read_nonblock(4096).strip
            rescue EOFError
              break
            rescue Errno::EWOULDBLOCK, Errno::EAGAIN
              cpuinfo = ''
              break # don't select file handle, just give up
            end
          end
        end
        processors = cpuinfo.split("\n").select {|line| line =~ /^processor\s*:/ }.size

        if processors == 0
          processors = 1 # assume there is at least one processor
          ::NewRelic::Agent.logger.warn("Cannot determine the number of processors in #{proc_file}")
        end
        processors
      end
    end
    
    # Grabs the architecture string from either `uname -p` or the env
    # variable PROCESSOR_ARCHITECTURE
    def gather_architecture_info
      append_environment_value('Arch') { `uname -p` } ||
        append_environment_value('Arch') { ENV['PROCESSOR_ARCHITECTURE'] }
    end
    
    # gathers OS info from either `uname -v`, `uname -s`, or the OS
    # env variable
    def gather_os_info
      append_environment_value('OS version') { `uname -v` }
      append_environment_value('OS') { `uname -s` } ||
        append_environment_value('OS') { ENV['OS'] }
    end
    
    # Gathers the architecture and cpu info
    def gather_system_info
      gather_architecture_info
      gather_cpu_info
    end
    
    # Looks for a capistrano file indicating the current revision
    def gather_revision_info
      rev_file = File.join(NewRelic::Control.instance.root, "REVISION")
      if File.readable?(rev_file) && File.size(rev_file) < 64
        append_environment_value('Revision') do
          File.open(rev_file) { | file | file.readline.strip }
        end
      end
    end
    
    # The name of the AR database adapter for the current environment and
    # the current schema version
    def gather_ar_adapter_info
      
      append_environment_value 'Database adapter' do
        if defined?(ActiveRecord) && defined?(ActiveRecord::Base) &&
            ActiveRecord::Base.respond_to?(:configurations)
          config = ActiveRecord::Base.configurations[NewRelic::Control.instance.env]
          if config
            config['adapter']
          end
        end
      end
    end
    
    # Datamapper version
    def gather_dm_adapter_info
      append_environment_value 'DataMapper version' do
        require 'dm-core/version'
        DataMapper::VERSION
      end
    end
    
    # sensing for which adapter is defined, then appends the relevant
    # config information
    def gather_db_info
      # room here for more database adapters, when.
      if defined? ::ActiveRecord
        gather_ar_adapter_info
      end
      if defined? ::DataMapper
        gather_dm_adapter_info
      end
    end

    # Collect base statistics about the environment and record them for
    # comparison and change detection.
    def gather_environment_info
      append_environment_value 'Framework', Agent.config[:framework].to_s
      append_environment_value 'Dispatcher', Agent.config[:dispatcher].to_s if Agent.config[:dispatcher]
      append_environment_value 'Dispatcher instance id', @dispatcher_instance_id if @dispatcher_instance_id
      append_environment_value('Environment') { NewRelic::Control.instance.env }

      # miscellaneous other helpful debugging information
      gather_ruby_info
      gather_system_info
      gather_revision_info
      gather_db_info
    end

    # Take a snapshot of the environment information for this application
    # Returns an associative array
    def snapshot
      i = @config.to_a
      i << [ 'Plugin List', @plugins.to_a] if not @plugins.empty?
      i << [ 'Gems', @gems.to_a] if not @gems.empty?
      i
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
      dispatchers = %w[passenger torquebox trinidad glassfish thin mongrel litespeed webrick fastcgi unicorn sinatra]
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

    def check_for_sinatra
      return unless defined?(::Sinatra) && defined?(::Sinatra::Base)

      begin
        version = ::Sinatra::VERSION
      rescue
        $stderr.puts("Error determining Sinatra version")
      end

      if ::NewRelic::VersionNumber.new('0.9.2') > version
        $stderr.puts("Your Sinatra version is #{version}, we highly recommend upgrading to >=0.9.2")
      end

      @discovered_dispatcher = :sinatra
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
