# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Configuration
      class EnvironmentSource < DottedHash
        SUPPORTED_PREFIXES = /^new_relic_|newrelic_|new_relic|newrelic/i

        attr_reader :alias_map, :config_types

        def initialize
          if ENV['NEW_RELIC_LOG']
            if ENV['NEW_RELIC_LOG'].upcase == 'STDOUT'
              self[:log_file_path] = self[:log_file_name] = 'STDOUT'
            else
              self[:log_file_path] = File.dirname(ENV['NEW_RELIC_LOG'])
              self[:log_file_name] = File.basename(ENV['NEW_RELIC_LOG'])
            end
          end

          @alias_map = {}
          @config_types = {}
          DEFAULTS.each do |config_setting, value|
            @config_types[config_setting] = value[:type]

            next unless value[:aliases]

            value[:aliases].each do |config_alias|
              @alias_map[config_alias] = config_setting
            end
          end

          set_values_from_new_relic_environment_variables
        end

        def set_values_from_new_relic_environment_variables
          nr_env_var_keys = collect_new_relic_environment_variable_keys

          nr_env_var_keys.each do |key|
            set_value_from_environment_variable(key)
          end
        end

        def set_value_from_environment_variable(key)
          config_key = convert_environment_key_to_config_key(key)

          # Only set keys that haven't been set by the previous map loops
          # TODO: Use default aliases to replace map loops
          set_key_by_type(config_key, key)
        end

        def set_key_by_type(config_key, environment_key)
          self[config_key] = ENV[environment_key] if self[config_key].nil?

          value = ENV[environment_key]
          type = self.config_types[config_key]

          if type == String
            self[config_key] = value
          elsif type == Fixnum
            self[config_key] = value.to_i
          elsif type == Float
            self[config_key] = value.to_f
          elsif type == Symbol
            self[config_key] = value.to_sym
          elsif type == NewRelic::Agent::Configuration::Boolean
            if value =~ /false|off|no/i
              self[config_key] = false
            elsif value != nil
              self[config_key] = true
            end
          end
        end

        def convert_environment_key_to_config_key(key)
          stripped_key = key.gsub(SUPPORTED_PREFIXES, '').downcase.to_sym
          self.alias_map[stripped_key] || stripped_key
        end

        def collect_new_relic_environment_variable_keys
          ENV.keys.select { |key| key.match(SUPPORTED_PREFIXES) }
        end

      end
    end
  end
end
