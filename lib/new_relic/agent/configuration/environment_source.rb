# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Configuration
      class EnvironmentSource < DottedHash
        SUPPORTED_PREFIXES = /new_relic_|newrelic_|nr_/i

        STRING_MAP = {
          'NRCONFIG'              => :config_path,
          'NEW_RELIC_LICENSE_KEY' => :license_key,
          'NEWRELIC_LICENSE_KEY'  => :license_key,
          'NEW_RELIC_APP_NAME'    => :app_name,
          'NEWRELIC_APP_NAME'     => :app_name,
          'NEW_RELIC_HOST'        => :host,
          'NEW_RELIC_PORT'        => :port
        }
        SYMBOL_MAP = {
          'NEW_RELIC_DISPATCHER'  => :dispatcher,
          'NEWRELIC_DISPATCHER'   => :dispatcher,
          'NEW_RELIC_FRAMEWORK'   => :framework,
          'NEWRELIC_FRAMEWORK'    => :framework
        }
        BOOLEAN_MAP = {
          'NEWRELIC_ENABLE'   => :agent_enabled,
          'NEWRELIC_ENABLED'  => :agent_enabled,
          'NEW_RELIC_ENABLE'  => :agent_enabled,
          'NEW_RELIC_ENABLED' => :agent_enabled,
          'NEWRELIC_DISABLE_HARVEST_THREAD'  => :disable_harvest_thread,
          'NEW_RELIC_DISABLE_HARVEST_THREAD' => :disable_harvest_thread
        }
        def initialize
          STRING_MAP.each do |key, val|
            self[val] = ENV[key] if ENV[key]
          end

          SYMBOL_MAP.each do |key, val|
            self[val] = ENV[key].intern if ENV[key]
          end

          BOOLEAN_MAP.each do |key, val|
            if ENV[key].to_s =~ /false|off|no/i
              self[val] = false
            elsif ENV[key] != nil
              self[val] = true
            end
          end

          if ENV['NEW_RELIC_LOG']
            if ENV['NEW_RELIC_LOG'].upcase == 'STDOUT'
              self[:log_file_path] = self[:log_file_name] = 'STDOUT'
            else
              self[:log_file_path] = File.dirname(ENV['NEW_RELIC_LOG'])
              self[:log_file_name] = File.basename(ENV['NEW_RELIC_LOG'])
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
          self[config_key] = ENV[key] if self[config_key].nil?
        end

        def convert_environment_key_to_config_key(key)
          key.gsub(SUPPORTED_PREFIXES, '').downcase.to_sym
        end

        def collect_new_relic_environment_variable_keys
          ENV.keys.select do |key|
            if key.match(SUPPORTED_PREFIXES)
              key
            end
          end
        end

      end
    end
  end
end
