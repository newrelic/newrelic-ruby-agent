require 'forwardable'
require 'new_relic/agent/configuration/defaults'
require 'new_relic/agent/configuration/yaml_source'
require 'new_relic/agent/configuration/environment_source'

module NewRelic
  module Agent
    module Configuration
      def self.manager
        @@manager ||= Manager.new
      end

      # This can be mixed in with minimal impact to provide easy
      # access to the config manager
      module Instance
        def config
          Configuration.manager
        end
      end

      class Manager
        def initialize
          @config_stack = [ EnvironmentSource.new, DEFAULTS ]
          yaml_config = YamlSource.new(NewRelic::Control.instance.root + '/' +
                                         self['config_path'],
                                       NewRelic::Control.instance.env)
          apply_config(yaml_config, 1)
        end

        def apply_config(source, level=0)
          @config_stack.insert(level, source)
        end

        def remove_config(source)
          @config_stack.delete(source)
        end

        def source(key)
          @config_stack.each do |config|
            if config.respond_to?(key) || config.has_key?(key)
              return config
            end
          end
        end

        # TODO this should be memoized
        def [](key)
          @config_stack.each do |config|
            if config.respond_to?(key)
              return config.send(key)
            elsif config.has_key?(key)
              if config[key].respond_to?(:call)
                return instance_eval(&config[key])
              else
                return config[key]
              end
            end
          end
          nil
        end

        # TODO this should be memoized
        def has_key?(key)
          @config_stack.each do |config|
            return true if config.has_key(key)
          end
          false
        end
      end

      class LegacySource
        extend Forwardable

        def settings
          NewRelic::Control.instance.settings
        end
        def_delegators :settings, :[], :has_key?

        def respond_to?(method)
          NewRelic::Control.instance.respond_to?(method) || super
        end

        def method_missing(method, *args)
          if respond_to?(method)
            NewRelic::Control.instance.send(method, *args)
          else
            super
          end
        end
      end
    end
  end
end
