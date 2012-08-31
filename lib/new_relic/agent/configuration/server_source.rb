module NewRelic
  module Agent
    module Configuration
      class ServerSource < DottedHash
        def initialize(hash)
          string_map = [
             ['collect_traces', :'transaction_tracer.enabled'],
             ['collect_traces', :'slow_sql.enabled'],
             ['collect_errors', :'error_collector.enabled']
          ].each do |pair|
            hash[pair[1]] = hash[pair[0]] if hash[pair[0]] != nil
          end

          if hash['transaction_tracer.transaction_threshold'] =~ /apdex_f/i
            # when value is "apdex_f" remove the config and defer to default
            hash.delete('transaction_tracer.transaction_threshold')
          end

          super
        end
      end
    end
  end
end
