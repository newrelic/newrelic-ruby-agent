# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'forwardable'
require 'new_relic/agent/configuration/mask_defaults'
require 'new_relic/agent/configuration/yaml_source'
require 'new_relic/agent/configuration/default_source'
require 'new_relic/agent/configuration/server_source'
require 'new_relic/agent/configuration/environment_source'

module NewRelic
  module Agent
    module Configuration
      class Manager
        attr_reader :stripped_exceptions_whitelist

        # Defining these explicitly saves object allocations that we incur
        # if we use Forwardable and def_delegators.
        def [](key)
          @cache[key]
        end

        def has_key?(key)
          @cache.has_key?[key]
        end

        def keys
          @cache.keys
        end

        def initialize
          reset_to_defaults
          @callbacks = Hash.new {|hash,key| hash[key] = [] }

          register_callback(:'strip_exception_messages.whitelist') do |whitelist|
            if whitelist
              @stripped_exceptions_whitelist = parse_constant_list(whitelist).compact
            else
              @stripped_exceptions_whitelist = []
            end
          end
        end

        def add_config_for_testing(source, level=0)
          raise 'Invalid config type for testing' unless [Hash, DottedHash].include?(source.class)
          invoke_callbacks(:add, source)
          @configs_for_testing << [source.freeze, level]
          reset_cache
          log_config(:add, source)
        end

        def remove_config_type(sym)
          source = case sym
          when :environment then @environment_source
          when :server      then @server_source
          when :manual      then @manual_source
          when :yaml        then @yaml_source
          when :default     then @default_source
          end

          remove_config(source)
        end

        def remove_config(source)
          case source
          when EnvironmentSource then @environment_source = nil
          when ServerSource      then @server_source      = nil
          when ManualSource      then @manual_source      = nil
          when YamlSource        then @yaml_source        = nil
          when DefaultSource     then @default_source     = nil
          else
            @configs_for_testing.delete_if {|src,lvl| src == source}
          end

          reset_cache
          invoke_callbacks(:remove, source)
          log_config(:remove, source)
        end

        def replace_or_add_config(source)
          source.freeze
          was_finished = finished_configuring?

          invoke_callbacks(:add, source)
          case source
          when EnvironmentSource then @environment_source = source
          when ServerSource      then @server_source      = source
          when ManualSource      then @manual_source      = source
          when YamlSource        then @yaml_source        = source
          when DefaultSource     then @default_source     = source
          else
            NewRelic::Agent.logger.warn("Invalid config format; config will be ignored: #{source}")
          end

          reset_cache
          log_config(:add, source)

          notify_finished_configuring if !was_finished && finished_configuring?
        end

        def source(key)
          config_stack.each do |config|
            if config.respond_to?(key.to_sym) || config.has_key?(key.to_sym)
              return config
            end
          end
        end

        def fetch(key)
          config_stack.each do |config|
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

        def notify_finished_configuring
          NewRelic::Agent.instance.events.notify(:finished_configuring)
        end

        def finished_configuring?
          !@server_source.nil?
        end

        def flattened
          config_stack.reverse.inject({}) do |flat,layer|
            thawed_layer = layer.to_hash.dup
            thawed_layer.each do |k,v|
              begin
                thawed_layer[k] = instance_eval(&v) if v.respond_to?(:call)
              rescue => e
                ::NewRelic::Agent.logger.debug("#{e.class.name} : #{e.message} - when accessing config key #{k}")
                thawed_layer[k] = nil
              end
              thawed_layer.delete(:config)
            end
            flat.merge(thawed_layer.to_hash)
          end
        end

        def apply_mask(hash)
          MASK_DEFAULTS. \
            select {|_, proc| proc.call}. \
            each {|key, _| hash.delete(key) }
          hash
        end

        def to_collector_hash
          DottedHash.new(apply_mask(flattened)).to_hash
        end

        def app_names
          case NewRelic::Agent.config[:app_name]
          when Array then NewRelic::Agent.config[:app_name]
          when String then NewRelic::Agent.config[:app_name].split(';')
          else []
          end
        end

        # Generally only useful during initial construction and tests
        def reset_to_defaults
          @environment_source  = EnvironmentSource.new
          @server_source       = nil
          @manual_source       = nil
          @yaml_source         = nil
          @default_source      = DefaultSource.new

          @configs_for_testing = []

          reset_cache
        end

        def reset_cache
          @cache = Hash.new {|hash,key| hash[key] = self.fetch(key) }
        end

        def log_config(direction, source)
          # Just generating this log message (specifically calling
          # flattened.inspect) is expensive enough that we don't want to do it
          # unless we're actually going to be logging the message based on our
          # current log level.
          ::NewRelic::Agent.logger.debug do
            "Updating config (#{direction}) from #{source.class}. Results: #{flattened.inspect}"
          end
        end

        def delete_all_configs_for_testing
          @environment_source  = nil
          @server_source       = nil
          @manual_source       = nil
          @yaml_source         = nil
          @default_source      = nil
          @configs_for_testing = []
        end

        def num_configs_for_testing
          config_stack.size
        end

        def config_classes_for_testing
          config_stack.map(&:class)
        end

        private

        def config_stack
          stack = [@environment_source,
                   @server_source,
                   @manual_source,
                   @yaml_source,
                   @default_source]

          stack.compact!

          @configs_for_testing.each do |config, index|
            stack.insert(index, config)
          end

          stack
        end

        def parse_constant_list(list)
          list.split(/\s*,\s*/).map do |class_name|
            const = constantize(class_name)

            unless const
              NewRelic::Agent.logger.warn "Configuration referenced undefined constant: #{class_name}"
            end

            const
          end
        end

        def constantize(class_name)
          namespaces = class_name.split('::')

          namespaces.inject(Object) do |namespace, name|
            return unless namespace
            namespace.const_get(name) if namespace.const_defined?(name)
          end
        end
      end
    end
  end
end
