# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Configuration
      class EnvironmentSource < DottedHash
        SUPPORTED_PREFIXES = /^new_relic_|^newrelic_/i
        SPECIAL_CASE_KEYS = [
          'NEW_RELIC_ENV', # read by NewRelic::Control::Frameworks::Ruby
          'NEW_RELIC_LOG', # read by set_log_file
          /^NEW_RELIC_METADATA_/ # read by NewRelic::Agent::Connect::RequestBuilder
        ]

        attr_accessor :alias_map

        def initialize
          set_log_file
          set_config_file

          @alias_map = {}

          DEFAULTS.each do |config_setting, value|
            set_aliases(config_setting, value)
          end

          set_values_from_new_relic_environment_variables
        end

        def set_aliases(config_setting, value)
          set_dotted_alias(config_setting)

          return unless value[:aliases]

          value[:aliases].each do |config_alias|
            self.alias_map[config_alias] = config_setting
          end
        end

        def set_dotted_alias(original_config_setting)
          config_setting = original_config_setting.to_s

          if config_setting.include?('.')
            config_alias = config_setting.tr('.', '_').to_sym
            self.alias_map[config_alias] = original_config_setting
          end
        end

        def set_log_file
          if ENV['NEW_RELIC_LOG']
            if ENV['NEW_RELIC_LOG'].casecmp(NewRelic::STANDARD_OUT) == 0
              self[:log_file_path] = self[:log_file_name] = NewRelic::STANDARD_OUT
            else
              self[:log_file_path] = File.dirname(ENV['NEW_RELIC_LOG'])
              self[:log_file_name] = File.basename(ENV['NEW_RELIC_LOG'])
            end
          end
        end

        def set_config_file
          self[:config_path] = ENV['NRCONFIG'] if ENV['NRCONFIG']
        end

        def set_values_from_new_relic_environment_variables
          nr_env_var_keys = collect_new_relic_environment_variable_keys

          nr_env_var_keys.each do |key|
            next if SPECIAL_CASE_KEYS.any? { |pattern| pattern === key.upcase }

            config_key = convert_environment_key_to_config_key(key)

            unless DEFAULTS.key?(config_key) || serverless?
              ::NewRelic::Agent.logger.info("#{key} does not have a corresponding configuration setting (#{config_key} does not exist).")
              ::NewRelic::Agent.logger.info('Run `rake newrelic:config:docs` or visit https://docs.newrelic.com/docs/apm/agents/ruby-agent/configuration/ruby-agent-configuration to see a list of available configuration settings.')
            end

            self[config_key] = ENV[key]
          end
        end

        def convert_environment_key_to_config_key(key)
          stripped_key = key.gsub(SUPPORTED_PREFIXES, '').downcase.to_sym
          self.alias_map[stripped_key] || stripped_key
        end

        def collect_new_relic_environment_variable_keys
          ENV.keys.select { |key| key.match(SUPPORTED_PREFIXES) }
        end

        # we can't rely on the :'serverless_mode.enabled' config parameter being
        # set yet to signify serverless mode given that we're in the midst of
        # building the config but we can always rely on the env var being set
        # by the Lambda layer
        def serverless?
          NewRelic::Agent::ServerlessHandler.env_var_set?
        end
      end
    end
  end
end
