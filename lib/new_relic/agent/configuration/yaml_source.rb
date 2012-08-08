module NewRelic
  module Agent
    module Configuration
      class YamlSource < ::Hash
        def initialize(path, env)
          file = File.read(File.expand_path(path))

          # Next two are for populating the newrelic.yml via erb binding, necessary
          # when using the default newrelic.yml file
          generated_for_user = ''
          license_key = ''

          erb = ERB.new(file).result(binding)
          config = merge!(YAML.load(erb)[env])

          # flatten to dotted notation
          self.merge!(dot_flattened(config))

          self.freeze
        end

        # turns {'a' => {'b' => 'c'}} into {'a.b' => 'c'}
        def dot_flattened(nested_hash, names=[], result={})
          nested_hash.each do |key, val|
            if val.respond_to?(:has_key?)
              dot_flattened(val, names + [key], result)
            else
              result[(names + [key]).join('.')] = val
            end
          end
          result
        end
      end
    end
  end
end
