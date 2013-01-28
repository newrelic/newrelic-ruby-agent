require 'new_relic/control/frameworks/ruby'
module NewRelic
  class Control
    module Frameworks
      # Control subclass instantiated when Rails is detected.  Contains
      # Rails specific configuration, instrumentation, environment values,
      # etc.
      class Rails < NewRelic::Control::Frameworks::Ruby

        def env
          @env ||= RAILS_ENV.dup
        end
        def root
          if defined?(RAILS_ROOT) && RAILS_ROOT.to_s != ''
            RAILS_ROOT.to_s
          else
            super
          end
        end

        def rails_config
          if defined?(::Rails) && ::Rails.respond_to?(:configuration)
            ::Rails.configuration
          else
            @config
          end
        end

        # In versions of Rails prior to 2.0, the rails config was only available to
        # the init.rb, so it had to be passed on from there.  This is a best effort to
        # find a config and use that.
        def init_config(options={})
          @config = options[:config]
          # Install the dependency detection,
          if rails_config && ::Rails.configuration.respond_to?(:after_initialize)
            rails_config.after_initialize do
              # This will insure we load all the instrumentation as late as possible.  If the agent
              # is not enabled, it will load a limited amount of instrumentation.  See
              # delayed_job_injection.rb
              DependencyDetection.detect!
            end
          end
          if !Agent.config[:agent_enabled]
            # Might not be running if it does not think mongrel, thin, passenger, etc
            # is running, if it thinks it's a rake task, or if the agent_enabled is false.
            ::NewRelic::Agent.logger.info("New Relic Agent not running.")
          else
            ::NewRelic::Agent.logger.info("Starting the New Relic Agent.")
            install_developer_mode rails_config if Agent.config[:developer_mode]
            install_browser_monitoring(rails_config)
          end
        end

        def install_browser_monitoring(config)
          return if @browser_monitoring_installed
          @browser_monitoring_installed = true
          return if config.nil? || !config.respond_to?(:middleware) || !Agent.config[:'browser_monitoring.auto_instrument']
          begin
            require 'new_relic/rack/browser_monitoring'
            config.middleware.use NewRelic::Rack::BrowserMonitoring
            ::NewRelic::Agent.logger.debug("Installed New Relic Browser Monitoring middleware")
          rescue => e
            ::NewRelic::Agent.logger.warn("Error installing New Relic Browser Monitoring middleware: #{e.inspect}")
          end
        end

        def install_developer_mode(rails_config)
          return if @installed
          @installed = true
          if rails_config && rails_config.respond_to?(:middleware)
            begin
              require 'new_relic/rack/developer_mode'
              rails_config.middleware.use NewRelic::Rack::DeveloperMode

              # inform user that the dev edition is available if we are running inside
              # a webserver process
              if @local_env.dispatcher_instance_id
                port = @local_env.dispatcher_instance_id.to_s =~ /^\d+/ ? ":#{local_env.dispatcher_instance_id}" : ":port"
                ::NewRelic::Agent.logger.debug("NewRelic Agent Developer Mode enabled.")
                ::NewRelic::Agent.logger.debug("To view performance information, go to http://localhost#{port}/newrelic")
              end
            rescue => e
              ::NewRelic::Agent.logger.warn("Error installing New Relic Developer Mode: #{e.inspect}")
            end
          elsif rails_config
            ::NewRelic::Agent.logger.warn("Developer mode not available for Rails versions prior to 2.2")
          end
        end

        def rails_version
          @rails_version ||= NewRelic::VersionNumber.new(::Rails::VERSION::STRING)
        end

        protected

        def rails_vendor_root
          File.join(root,'vendor','rails')
        end

        def rails_gem_list
          ::Rails.configuration.gems.map do |gem|
            version = (gem.respond_to?(:version) && gem.version) ||
              (gem.specification.respond_to?(:version) && gem.specification.version)
            gem.name + (version ? "(#{version})" : "")
          end
        end

        # Collect the Rails::Info into an associative array as well as the list of plugins
        def append_environment_info
          local_env.append_environment_value('Rails version'){ ::Rails::VERSION::STRING }
          if rails_version >= NewRelic::VersionNumber.new('2.2.0')
            local_env.append_environment_value('Rails threadsafe') do
              ::Rails.configuration.action_controller.allow_concurrency == true
            end
          end
          local_env.append_environment_value('Rails Env') { ENV['RAILS_ENV'] }
          if rails_version >= NewRelic::VersionNumber.new('2.1.0')
            local_env.append_gem_list do
              (bundler_gem_list + rails_gem_list).uniq
            end
            # The plugins is configured manually.  If it's nil, it loads everything non-deterministically
            if ::Rails.configuration.plugins
              local_env.append_plugin_list { ::Rails.configuration.plugins }
            else
              ::Rails.configuration.plugin_paths.each do |path|
                local_env.append_plugin_list { Dir[File.join(path, '*')].collect{ |p| File.basename p if File.directory? p }.compact }
              end
            end
          else
            # Rails prior to 2.1, can't get the gems.  Find plugins in the default location
            local_env.append_plugin_list do
              Dir[File.join(root, 'vendor', 'plugins', '*')].collect{ |p| File.basename p if File.directory? p }.compact
            end
          end
        end

        def install_shim
          super
          require 'new_relic/agent/instrumentation/controller_instrumentation'
          if ActiveSupport.respond_to?(:on_load) # rails 3+
            ActiveSupport.on_load(:action_controller) { include NewRelic::Agent::Instrumentation::ControllerInstrumentation::Shim }
          else
            ActionController::Base.class_eval { include NewRelic::Agent::Instrumentation::ControllerInstrumentation::Shim }
          end
        end
      end
    end
  end
end
