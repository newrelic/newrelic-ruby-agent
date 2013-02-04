require 'new_relic/control/frameworks/rails'
require 'new_relic/rack/error_collector'
module NewRelic
  class Control
    module Frameworks
      # Control subclass instantiated when Rails is detected.  Contains
      # Rails 3.0+  specific configuration, instrumentation, environment values,
      # etc. Many methods are inherited from the
      # NewRelic::Control::Frameworks::Rails class, where the two do
      # not differ
      class Rails3 < NewRelic::Control::Frameworks::Rails

        def env
          @env ||= ::Rails.env.to_s
        end

        def rails_root
          ::Rails.root.to_s
        end

        def init_config(options={})
          super
          if Agent.config[:agent_enabled] && Agent.config[:'error_collector.enabled']
            if !rails_config.middleware.respond_to?(:include?) ||
                !rails_config.middleware.include?(NewRelic::Rack::ErrorCollector)
              add_error_collector_middleware
            end
          end
        end

        def add_error_collector_middleware
          rails_config.middleware.use NewRelic::Rack::ErrorCollector
        end

        def vendor_root
          @vendor_root ||= File.join(root,'vendor','rails')
        end

        def version
          @rails_version ||= NewRelic::VersionNumber.new(::Rails::VERSION::STRING)
        end

        protected

        # Collect the Rails::Info into an associative array as well as the list of plugins
        def append_environment_info
          local_env.append_environment_value('Rails version'){ ::Rails::VERSION::STRING }
          local_env.append_environment_value('Rails threadsafe') do
            true == ::Rails.configuration.action_controller.allow_concurrency
          end
          local_env.append_environment_value('Rails Env') { env }
          local_env.append_gem_list do
            bundler_gem_list
          end
          append_plugin_list
        end

        def append_plugin_list
          local_env.append_plugin_list { ::Rails.configuration.plugins.to_a }
        end
        
        def install_shim
          super
          ActiveSupport.on_load(:action_controller) do
            include NewRelic::Agent::Instrumentation::ControllerInstrumentation::Shim
          end
        end
      end
    end
  end
end
