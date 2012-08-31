require 'new_relic/agent/configuration'

module NewRelic
  module Agent
    module Configuration
      class YamlSource < DottedHash
        attr_accessor :file_path

        def initialize(path, env)
          config = {}
          begin
            @file_path = File.expand_path(path)
            if !File.exists?(@file_path)
              NewRelic::Control.instance.log.error("Unable to load configuration from #{path}")
              return
            end

            file = File.read(@file_path)

            # Next two are for populating the newrelic.yml via erb binding, necessary
            # when using the default newrelic.yml file
            generated_for_user = ''
            license_key = ''

            erb = ERB.new(file).result(binding)
            config = merge!(YAML.load(erb)[env] || {})
          rescue ScriptError, StandardError => e
            NewRelic::Control.instance.log.warn("Unable to read configuration file: #{e}")
          end

          if config['transaction_tracer'] &&
              config['transaction_tracer']['transaction_threshold'] =~ /apdex_f/i
            # when value is "apdex_f" remove the config and defer to default
            config['transaction_tracer'].delete('transaction_threshold')
          end

          booleanify_values(config, 'agent_enabled', 'enabled', 'monitor_daemons')

          super(config)
        end

        protected

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
      end
    end
  end
end
