# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/configuration/dotted_hash'

module NewRelic
  module Agent
    module Configuration
      class YamlSource < DottedHash
        attr_accessor :file_path, :failures

        def initialize(path, env)
          config    = {}
          @failures = []

          begin
            @file_path = validate_config_file_path(path)
            return unless @file_path

            ::NewRelic::Agent.logger.info("Reading configuration from #{path} (#{Dir.pwd})")
            raw_file = File.read(@file_path)
            erb_file = process_erb(raw_file)
            config   = process_yaml(erb_file, env, config, @file_path)
          rescue ScriptError, StandardError => e
            log_failure("Failed to read or parse configuration file at #{path}", e)
          end

          substitute_transaction_threshold(config)
          booleanify_values(config, 'agent_enabled', 'enabled')

          super(config, true)
        end

        def failed?
          !@failures.empty?
        end

        protected

        def validate_config_file_path(path)
          expanded_path = File.expand_path(path)

          if path.empty? || !File.exist?(expanded_path)
            warn_missing_config_file(expanded_path)
            return
          end

          expanded_path
        end

        def warn_missing_config_file(path)
          based_on        = 'unknown'
          source          = ::NewRelic::Agent.config.source(:config_path)
          candidate_paths = [path]

          case source
          when DefaultSource
            based_on = 'defaults'
            candidate_paths = NewRelic::Agent.config[:config_search_paths].map do |p|
              File.expand_path(p)
            end
          when EnvironmentSource
            based_on = 'environment variable'
          when ManualSource
            based_on = 'API call'
          end

          # This is not a failure, since we do support running without a
          # newrelic.yml (configured with just ENV). It is, however, uncommon,
          # so warn about it since it's very likely to be unintended.
          NewRelic::Agent.logger.warn(
            "No configuration file found. Working directory = #{Dir.pwd}",
            "Looked in these locations (based on #{based_on}): #{candidate_paths.join(", ")}"
          )
        end

        def process_erb(file)
          begin
            # Exclude lines that are commented out so failing Ruby code in an
            # ERB template commented at the YML level is fine. Leave the line,
            # though, so ERB line numbers remain correct.
            file.gsub!(/^\s*#.*$/, '#')

            # Next two are for populating the newrelic.yml via erb binding, necessary
            # when using the default newrelic.yml file
            generated_for_user = ''
            license_key = ''

            ERB.new(file).result(binding)
          rescue ScriptError, StandardError => e
            log_failure("Failed ERB processing configuration file. This is typically caused by a Ruby error in <% %> templating blocks in your newrelic.yml file.", e)
            nil
          ensure
            # Avoid warnings by using these again
            generated_for_user = nil
            license_key = nil
          end
        end

        def process_yaml(file, env, config, path)
          if file
            confighash = with_yaml_engine { YAML.load(file) }
            unless confighash.key?(env)
              log_failure("Config file at #{path} doesn't include a '#{env}' section!")
            end

            config = confighash[env] || {}
          end

          config
        end

        def substitute_transaction_threshold(config)
          if config['transaction_tracer'] &&
              config['transaction_tracer']['transaction_threshold'] =~ /apdex_f/i
            # when value is "apdex_f" remove the config and defer to default
            config['transaction_tracer'].delete('transaction_threshold')
          end
        end

        def with_yaml_engine
          return yield unless NewRelic::LanguageSupport.needs_syck?

          yamler = ::YAML::ENGINE.yamler
          ::YAML::ENGINE.yamler = 'syck'
          result = yield
          ::YAML::ENGINE.yamler = yamler
          result
        end


        def booleanify_values(config, *keys)
          # auto means defer ro default
          keys.each do |option|
            if config[option] == 'auto'
              config.delete(option)
            elsif !config[option].nil? && !is_boolean?(config[option])
              config[option] = !!(config[option] =~ /yes|on|true/i)
            end
          end
        end

        def is_boolean?(value)
          value == !!value
        end

        def log_failure(*messages)
          ::NewRelic::Agent.logger.error(*messages)
          @failures << messages
        end
      end
    end
  end
end
