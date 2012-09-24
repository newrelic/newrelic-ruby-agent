require 'forwardable'
require 'new_relic/agent/configuration/defaults'
require 'new_relic/agent/configuration/yaml_source'
require 'new_relic/agent/configuration/server_source'
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
          @callbacks = Hash.new {|hash,key| hash[key] = [] }
        end

        def apply_config(source, level=0)
          invoke_callbacks(:add, source)
          @config_stack.insert(level, source.freeze)
          reset_cache
        end

        def remove_config(source=nil)
          if block_given?
            @config_stack.delete_if {|c| yield c }
          else
            @config_stack.delete(source)
          end
          reset_cache
          invoke_callbacks(:remove, source)
        end

        def replace_or_add_config(source, level=0)
          idx = @config_stack.map{|s| s.class}.index(source.class)
          @config_stack.delete_at(idx) if idx
          apply_config(source, idx || level)
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
            if config.has_key?(accessor)
              if config[accessor].respond_to?(:call)
                return instance_eval(&config[accessor])
              else
                return config[accessor]
              end
            end
          end
          nil
        end

        def register_callback(key, &proc)
          @callbacks[key] << proc
          proc.call(@cache[key])
        end

        def invoke_callbacks(direction, source)
          return unless source
          source.keys.each do |key|
            if @cache[key] != source[key]
              @callbacks[key].each do |proc|
                if direction == :add
                  proc.call(source[key])
                else
                  proc.call(@cache[key])
                end
              end
            end
          end
        end

        def flattened_config
          @config_stack.reverse.inject({}) do |flat,layer|
            thawed_layer = layer.dup
            thawed_layer.each do |k,v|
              begin
                thawed_layer[k] = instance_eval(&v) if v.respond_to?(:call)
              rescue => e
                NewRelic::Control.instance.log.debug("#{e.class.name} : #{e.message} - when accessing config key #{k}")
                thawed_layer[k] = nil
              end
              thawed_layer.delete(:config)
            end
            flat.merge(thawed_layer)
          end
        end

        def app_names
          case self[:app_name]
          when Array then self[:app_name]
          when String then self[:app_name].split(';')
          else []
          end
        end

        def reset_cache
          @cache = Hash.new {|hash,key| hash[key] = self.fetch(key) }
        end
      end
    end
  end
end
