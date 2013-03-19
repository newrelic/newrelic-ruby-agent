# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Configuration
      class ServerSource < DottedHash
        def initialize(hash, existing_config={})
          if hash['agent_config']
            if hash['agent_config']['transaction_tracer.transaction_threshold'] =~ /apdex_f/i
              # when value is "apdex_f" remove the config and defer to default
              hash['agent_config'].delete('transaction_tracer.transaction_threshold')
            end
            super(hash.delete('agent_config'))
          end

          if hash['web_transactions_apdex']
            self[:web_transactions_apdex] = hash.delete('web_transactions_apdex')
          end
          apply_feature_gates(hash, existing_config)

          super(hash)
        end

        # These feature gates are not intended to be bullet-proof, but only to
        # avoid the overhead of collecting and transmitting additional data if
        # the user's subscription level precludes its use. The server is the
        # ultimate authority regarding subscription levels, so we expect it to
        # do the real enforcement there.
        def apply_feature_gates(hash, existing_config)
          gated_features = {
            :'transaction_tracer.enabled' => 'collect_traces',
            :'slow_sql.enabled'           => 'collect_traces',
            :'error_collector.enabled'    => 'collect_errors'
          }
          gated_features.each do |feature, gate_key|
            unless hash[gate_key].nil?
              existing_value = existing_config[feature]
              allowed_by_server = hash[gate_key]
              hash[feature] = (allowed_by_server && existing_value)
            end
          end
        end
      end
    end
  end
end
