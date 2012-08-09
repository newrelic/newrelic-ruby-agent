require 'new_relic/agent/configuration/manager'

module NewRelic
  module Agent
    module Configuration
      def self.manager
        @@manager ||= Manager.new
      end

      # This can be mixed in with minimal impact to provide easy
      # access to the config manager
      module Instance
        def config
          Configuration.manager
        end
      end

      class DottedHash < ::Hash
        def initialize(hash)
          self.merge!(dot_flattened(hash))
          self.freeze
        end

        protected
        # turns {'a' => {'b' => 'c'}} into {'a.b' => 'c'}
        def dot_flattened(nested_hash, names=[], result={})
          nested_hash.each do |key, val|
            next if val == nil
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
