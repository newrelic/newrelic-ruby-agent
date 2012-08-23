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
          keys.each do |key|
            self[(key.to_sym rescue key) || key] = delete(key)
          end
        end

        def inspect
          "#<#{self.class.name}:#{object_id} #{super}>"
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

      class ManualSource < DottedHash; end

      class ServerSource < DottedHash
        def initialize(hash)
          string_map = [
            ['collect_traces', 'transaction_tracer.enabled'],
            ['collect_traces', 'slow_sql.enabled']
          ].each do |pair|
            self[pair[1]] = hash[pair[0]] if hash[pair[0]] != nil
          end
          super
        end
      end
    end
  end
end
