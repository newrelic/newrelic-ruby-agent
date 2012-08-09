require 'new_relic/agent/configuration'

module NewRelic
  module Agent
    module Configuration
      class YamlSource < DottedHash
        def initialize(path, env)
          if !File.exists?(File.expand_path(path))
            NewRelic::Control.instance.log.error('Unable to load configuration from #{path}')
            return
          end

          file = File.read(File.expand_path(path))

          # Next two are for populating the newrelic.yml via erb binding, necessary
          # when using the default newrelic.yml file
          generated_for_user = ''
          license_key = ''

          erb = ERB.new(file).result(binding)
          config = merge!(YAML.load(erb)[env])

          if config['transaction_tracer'] &&
              config['transaction_tracer']['transaction_threshold'] =~ /apdex_f/i
            config['transaction_tracer'].delete('transaction_threshold')
          end

          super(config)
        end

        def inspect
          "#<YamlSource:#{object_id} #{super}>"
        end
      end
    end
  end
end
