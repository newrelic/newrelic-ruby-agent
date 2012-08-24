require 'forwardable'
require 'new_relic/agent/configuration/defaults'
require 'new_relic/agent/configuration/yaml_source'
require 'new_relic/agent/configuration/environment_source'

module NewRelic
  module Agent
    module Configuration
      class Manager
        extend Forwardable
        def_delegators :@cache, :[], :has_key?
        attr_reader :config_stack # mainly for testing

        def initialize
          @config_stack = [ EnvironmentSource.new, DEFAULTS ]
          @cache = Hash.new {|hash,key| hash[key] = self.fetch(key) }

          # letting Control handle this for now
#           yaml_config = YamlSource.new("#{NewRelic::Control.instance.root}/#{self['config_path']}",
#                                        NewRelic::Control.instance.env)
#           apply_config(yaml_config, 1) if yaml_config
        end

        def apply_config(source, level=0)
          @config_stack.insert(level, source.freeze)
          expire_cache
        end

        def remove_config(source=nil)
          if block_given?
            @config_stack.delete_if {|c| yield c }
          else
            @config_stack.delete(source)
          end
          expire_cache
        end

        def source(key)
          @config_stack.each do |config|
            if config.respond_to?(key.to_sym) || config.has_key?(key.to_sym)
              return config
            end
          end
        end

        def fetch(key)
          @config_stack.each do |config|
            next unless config
            accessor = key.to_sym
            if config.respond_to?(accessor)
              return config.send(accessor)
            elsif config.has_key?(accessor)
              if config[accessor].respond_to?(:call)
                return instance_eval(&config[accessor])
              else
                return config[accessor]
              end
            end
          end
          nil
        end

        def flattened_config
          @config_stack.reverse.inject({}) do |flat,stack|
            thawed_stack = stack.dup
            thawed_stack.each do |k,v|
              thawed_stack[k] = instance_eval(&v) if v.respond_to?(:call)
            end
            flat.merge(thawed_stack)
          end
        end

        def app_names
          case self[:app_name]
          when Array then self[:app_name]
          when String then self[:app_name].split(';')
          end
        end

        def expire_cache
          @cache = Hash.new {|hash,key| hash[key] = self.fetch(key) }
        end
      end
    end
  end
end
