require 'new_relic/agent/configuration/defaults'
require 'new_relic/agent/configuration/yaml_source'
require 'new_relic/agent/configuration/environment_source'

module NewRelic
  module Agent
    module Configuration
      class Manager
        attr_accessor :config_stack # mainly for testing

        def initialize
          @config_stack = [ EnvironmentSource.new, DEFAULTS ]
          # letting Control handle this for now
#           yaml_config = YamlSource.new("#{NewRelic::Control.instance.root}/#{self['config_path']}",
#                                        NewRelic::Control.instance.env)
#           apply_config(yaml_config, 1) if yaml_config
        end

        def apply_config(source, level=0)
          @config_stack.insert(level, source)
        end

        def remove_config(source=nil)
          if block_given?
            @config_stack.delete_if {|c| yield c }
          else
            @config_stack.delete(source)
          end
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
            next unless config
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
            next unless config
            return true if config.has_key(key)
          end
          false
        end

        def app_names
          case self['app_name']
          when Array then self['app_name']
          when String then self['app_name'].split(';')
          end
        end
      end
    end
  end
end
