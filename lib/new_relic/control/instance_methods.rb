require 'new_relic/language_support'

module NewRelic
  class Control
    include NewRelic::LanguageSupport::Control

    # Contains methods that relate to the runtime usage of the control
    # object. Note that these are subject to override in the
    # NewRelic::Control::Framework classes that are actually instantiated
    module InstanceMethods
      # The env is the setting used to identify which section of the newrelic.yml
      # to load.  This defaults to a framework specific value, such as ENV['RAILS_ENV']
      # but can be overridden as long as you set it before calling #init_plugin
      attr_writer :env

      # The local environment contains all the information we report
      # to the server about what kind of application this is, what
      # gems and plugins it uses, and many other kinds of
      # machine-dependent information useful in debugging
      attr_reader :local_env


      # Initialize the plugin/gem and start the agent.  This does the
      # necessary configuration based on the framework environment and
      # determines whether or not to start the agent.  If the agent is
      # not going to be started then it loads the agent shim which has
      # stubs for all the external api.
      #
      # This may be invoked multiple times, as long as you don't attempt
      # to uninstall the agent after it has been started.
      #
      # If the plugin is initialized and it determines that the agent is
      # not enabled, it will skip starting it and install the shim.  But
      # if you later call this with <tt>:agent_enabled => true</tt>,
      # then it will install the real agent and start it.
      #
      # What determines whether the agent is launched is the result of
      # calling agent_enabled?  This will indicate whether the
      # instrumentation should/will be installed.  If we're in a mode
      # where tracers are not installed then we should not start the
      # agent.
      #
      # Subclasses are not allowed to override, but must implement
      # init_config({}) which is called one or more times.
      #
      def init_plugin(options={})
        begin
          path = @newrelic_file || Agent.config[:config_path]
          yaml = Agent::Configuration::YamlSource.new(path, env)
          Agent.config.replace_or_add_config(yaml, 1)
        rescue ScriptError, StandardError => e
          # Why do we need to do this?
          new_err = e.class.new("Error reading newrelic.yml file: #{e}")
          new_err.set_backtrace(e.backtrace)
          raise new_err
        end

        Agent.config.replace_or_add_config(Agent::Configuration::ManualSource.new(options), 1)
        options['app_name'] = ENV['NEWRELIC_APP_NAME'] if ENV['NEWRELIC_APP_NAME']
        options['app_name'] ||= ENV['NEW_RELIC_APP_NAME'] if ENV['NEW_RELIC_APP_NAME']

        # Merge the stringified options into the config as overrides:
        logger_override = options.delete(:log)
        environment_name = options.delete(:env) and self.env = environment_name
        dispatcher = options.delete(:dispatcher) and @local_env.dispatcher = dispatcher
        dispatcher_instance_id = options.delete(:dispatcher_instance_id) and @local_env.dispatcher_instance_id = dispatcher_instance_id

        NewRelic::Agent::PipeChannelManager.listener.start if options.delete(:start_channel_listener)

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
        if Agent.config[:agent_enabled] && !NewRelic::Agent.instance.started?
          setup_log unless logger_override
          start_agent
          install_instrumentation
          load_samplers unless Agent.config['disable_samplers']
          local_env.gather_environment_info
          append_environment_info
        elsif !Agent.config[:agent_enabled]
          install_shim
        end
      end

      # Install the real agent into the Agent module, and issue the start command.
      def start_agent
        NewRelic::Agent.agent.start
      end

      # Asks the LocalEnvironment instance which framework should be loaded
      def app
        @local_env.framework
      end
      alias framework app

      def to_s #:nodoc:
        "Control[#{self.app}]"
      end

      # for backward compatibility with the old config interface
      def [](key)
        NewRelic::Agent.config[key.to_sym]
      end

      def settings
        NewRelic::Agent.config.flattened_config
      end

      def dispatcher
        NewRelic::Agent.config[:dispatcher]
      end

      protected

      # Append framework specific environment information for uploading to
      # the server for change detection.  Override in subclasses
      def append_environment_info; end

      # Asks bundler to tell us which gemspecs are loaded in the
      # current process
      def bundler_gem_list
        if defined?(Bundler) && Bundler.instance_eval do @load end
          Bundler.load.specs.map do |spec|
            version = (spec.respond_to?(:version) && spec.version)
            spec.name + (version ? "(#{version})" : "")
          end
        else
          []
        end
      end

      # path to the config file, defaults to the "#{root}/config/newrelic.yml"
      def config_file
        File.expand_path(File.join(root,"config","newrelic.yml"))
      end

      def initialize local_env, config_file_override=nil
        @local_env = local_env
        @instrumentation_files = []
        @newrelic_file = config_file_override || config_file
      end

      def root
        '.'
      end

      # Delegates to the class method newrelic_root, implemented by
      # each subclass
      def newrelic_root
        self.class.newrelic_root
      end
    end
    include InstanceMethods
  end
end
