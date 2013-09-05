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
        extend Forwardable
        def_delegators :@cache, :[], :has_key?, :keys
        attr_reader :config_stack, :stripped_exceptions_whitelist

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

        def apply_config(source, level=0)
          was_finished = finished_configuring?

          invoke_callbacks(:add, source)
          @config_stack.insert(level, source.freeze)
          reset_cache
          log_config(:add, source)

          notify_finished_configuring if !was_finished && finished_configuring?
        end

        def remove_config(source=nil)
          if block_given?
            @config_stack.delete_if {|c| yield c }
          else
            @config_stack.delete(source)
          end
          reset_cache
          invoke_callbacks(:remove, source)
          log_config(:remove, source)
        end

        def replace_or_add_config(source, level=0)
          index = @config_stack.map{|s| s.class}.index(source.class)
          @config_stack.delete_at(index) if index
          apply_config(source, index || level)
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

        def notify_finished_configuring
          NewRelic::Agent.instance.events.notify(:finished_configuring)
        end

        def finished_configuring?
          @config_stack.any? {|s| s.is_a?(ServerSource)}
        end

        def flattened
          @config_stack.reverse.inject({}) do |flat,layer|
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
          case self[:app_name]
          when Array then self[:app_name]
          when String then self[:app_name].split(';')
          else []
          end
        end

        # Generally only useful during initial construction and tests
        def reset_to_defaults
          @config_stack = [ EnvironmentSource.new, DefaultSource.new ]
          reset_cache
        end

        def reset_cache
          @cache = Hash.new {|hash,key| hash[key] = self.fetch(key) }
        end

        def log_config(direction, source)
          ::NewRelic::Agent.logger.debug(
            "Updating config (#{direction}) from #{source.class}. Results:",
            flattened.inspect)
        end

        private

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
