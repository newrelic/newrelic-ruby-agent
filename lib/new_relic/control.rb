require 'yaml'
require 'new_relic/local_environment'
require 'singleton'
require 'erb'
require 'socket'
require 'net/https'
require 'logger'
require 'new_relic/control/profiling'
require 'new_relic/control/logging_methods'
require 'new_relic/control/configuration'
require 'new_relic/control/server_methods'
require 'new_relic/control/instrumentation'

module NewRelic

  # The Control is a singleton responsible for the startup and
  # initialization sequence.  The initializer uses a LocalEnvironment to
  # detect the framework and instantiates the framework specific
  # subclass.
  #
  # The Control also implements some of the public API for the agent.
  #
  class Control
    # used for framework-specific subclasses
    module Frameworks; end

    include Profiling
    include LoggingMethods
    include Configuration
    include ServerMethods
    include Instrumentation

    # The env is the setting used to identify which section of the newrelic.yml
    # to load.  This defaults to a framework specific value, such as ENV['RAILS_ENV']
    # but can be overridden as long as you set it before calling #init_plugin
    attr_writer :env

    attr_reader :local_env

    module ClassMethods
      # Access the Control singleton, lazy initialized
      def instance
        @instance ||= new_instance
      end

      # Create the concrete class for environment specific behavior:
      def new_instance
        @local_env = NewRelic::LocalEnvironment.new
        if @local_env.framework == :test
          # You can set this env var if you want to run the tests
          # without Rails.
          config = File.expand_path("../../../test/config/newrelic.yml", __FILE__)
          if ENV['SKIP_RAILS']
            require "new_relic/control/frameworks/ruby.rb"
            NewRelic::Control::Frameworks::Ruby.new @local_env, config
          else
            require "config/test_control"
            NewRelic::Control::Frameworks::Test.new @local_env, config
          end
        else
          begin
            require "new_relic/control/frameworks/#{@local_env.framework}.rb"
          rescue LoadError
          end
          NewRelic::Control::Frameworks.const_get(@local_env.framework.to_s.capitalize).new @local_env
        end
      end

      # The root directory for the plugin or gem
      def newrelic_root
        File.expand_path("../../..", __FILE__)
      end
    end
    extend ClassMethods

    # Initialize the plugin/gem and start the agent.  This does the necessary configuration based on the
    # framework environment and determines whether or not to start the agent.  If the
    # agent is not going to be started then it loads the agent shim which has stubs
    # for all the external api.
    #
    # This may be invoked multiple times, as long as you don't attempt to uninstall
    # the agent after it has been started.
    #
    # If the plugin is initialized and it determines that the agent is not enabled, it
    # will skip starting it and install the shim.  But if you later call this with
    # <tt>:agent_enabled => true</tt>, then it will install the real agent and start it.
    #
    # What determines whether the agent is launched is the result of calling agent_enabled?
    # This will indicate whether the instrumentation should/will be installed.  If we're
    # in a mode where tracers are not installed then we should not start the agent.
    #
    # Subclasses are not allowed to override, but must implement init_config({}) which
    # is called one or more times.
    #
    def init_plugin(options={})
      require 'conditional_vendored_metric_parser'
      
      options['app_name'] = ENV['NEWRELIC_APP_NAME'] if ENV['NEWRELIC_APP_NAME']

      require 'new_relic/agent'

      # Load the DJ injection now.  If you do it sooner, DJ might not be loaded and
      # you'll miss it.
      require 'new_relic/delayed_job_injection'

      # Merge the stringified options into the config as overrides:
      logger_override = options.delete(:log)
      environment_name = options.delete(:env) and self.env = environment_name
      dispatcher = options.delete(:dispatcher) and @local_env.dispatcher = dispatcher
      dispatcher_instance_id = options.delete(:dispatcher_instance_id) and @local_env.dispatcher_instance_id = dispatcher_instance_id

      # Clear out the settings, if they've already been loaded.  It may be that
      # between calling init_plugin the first time and the second time, the env
      # has been overridden
      @settings = nil
      settings
      merge_options(options)
      if logger_override
        @log = logger_override
        # Try to grab the log filename
        @log_file = @log.instance_eval { @logdev.filename rescue nil }
      end
      # An artifact of earlier implementation, we put both #add_method_tracer and #trace_execution
      # methods in the module methods.
      Module.send :include, NewRelic::Agent::MethodTracer::ClassMethods
      Module.send :include, NewRelic::Agent::MethodTracer::InstanceMethods
      init_config(options)
      NewRelic::Agent.agent = NewRelic::Agent::Agent.instance
      if agent_enabled? && !NewRelic::Agent.instance.started?
        setup_log unless logger_override
        start_agent
        install_instrumentation
        load_samplers unless self['disable_samplers']
        local_env.gather_environment_info
        append_environment_info
      elsif !agent_enabled?
        install_shim
      end
    end

    # Install the real agent into the Agent module, and issue the start command.
    def start_agent
      NewRelic::Agent.agent.start
    end

    # True if dev mode or monitor mode are enabled, and we are running
    # inside a valid dispatcher like mongrel or passenger.  Can be overridden
    # by NEWRELIC_ENABLE env variable, monitor_daemons config option when true, or
    # agent_enabled config option when true or false.
    def agent_enabled?
      return false if !developer_mode? && !monitor_mode?
      return self['agent_enabled'].to_s =~ /true|on|yes/i if !self['agent_enabled'].nil? && self['agent_enabled'] != 'auto'
      return false if ENV['NEWRELIC_ENABLE'].to_s =~ /false|off|no/i
      return true if self['monitor_daemons'].to_s =~ /true|on|yes/i
      return true if ENV['NEWRELIC_ENABLE'].to_s =~ /true|on|yes/i
      # When in 'auto' mode the agent is enabled if there is a known
      # dispatcher running
      return true if @local_env.dispatcher != nil
    end

    def app
      @local_env.framework
    end
    alias framework app

    def to_s
      "Control[#{self.app}]"
    end

    protected

    # Append framework specific environment information for uploading to
    # the server for change detection.  Override in subclasses
    def append_environment_info; end

    def bundler_gem_list
      if defined?(Bundler) && Bundler.instance_eval do @load end
        Bundler.load.specs.map do | spec |
          version = (spec.respond_to?(:version) && spec.version)
          spec.name + (version ? "(#{version})" : "")
        end
      else
        []
      end
    end
    
    def config_file
      File.expand_path(File.join(root,"config","newrelic.yml"))
    end

    def initialize local_env, config_file_override=nil
      @local_env = local_env
      @instrumentation_files = []
      newrelic_file = config_file_override || config_file
      # Next two are for populating the newrelic.yml via erb binding, necessary
      # when using the default newrelic.yml file
      generated_for_user = ''
      license_key=''
      if !File.exists?(newrelic_file)
        log! "Cannot find read #{newrelic_file}."
        @yaml = {}
      else
        @yaml = YAML.load(ERB.new(File.read(newrelic_file)).result(binding))
      end
    rescue ScriptError, StandardError => e
      puts e
      puts e.backtrace.join("\n")
      raise "Error reading newrelic.yml file: #{e}"
    end

    def newrelic_root
      self.class.newrelic_root
    end

  end
end
