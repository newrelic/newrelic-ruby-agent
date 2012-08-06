module NewRelic
  module Agent
    module Configuration
      def self.manager
        @manager ||= Manager.new
      end
      
      class Manager
        def initialize
          @config_stack = [ DefaultSource.new ]
        end

        def apply_config(source, level=0)
          @config_stack.insert(level, source)
        end

        def source(key)
          @config_stack.each do |config|
            return config.class if config.has_key?(key)
          end
        end
        
        def [](key)
          @config_stack.each do |config|
            if config.has_key?(key)
              if config[key].respond_to?(:call)
                return instance_eval &config[key]
              else
                return config[key]
              end
            end
          end
        end
        alias_method :fetch, :[]
        
      end

      class LegacySource
        def method_missing(method, *args)
          NewRelic::Control.instance.settings.send(method, *args)
        end
      end

      class DefaultSource < ::Hash; end
    end
  end
end
