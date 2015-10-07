# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Configuration
      class ServerSource < DottedHash
        # These keys appear *outside* of the agent_config hash in the connect
        # response, but should still be merged in as config settings to the
        # main agent configuration.
        TOP_LEVEL_KEYS = [
          "apdex_t",
          "application_id",
          "beacon",
          "browser_key",
          "browser_monitoring.debug",
          "browser_monitoring.loader",
          "browser_monitoring.loader_version",
          "cross_process_id",
          "data_report_period",
          "data_report_periods.analytic_event_data",
          "encoding_key",
          "error_beacon",
          "js_agent_file",
          "js_agent_loader",
          "trusted_account_ids"
        ]

        def initialize(connect_reply, existing_config={})
          merged_settings = {}

          merge_top_level_keys(merged_settings, connect_reply)
          merge_agent_config_hash(merged_settings, connect_reply)
          fix_transaction_threshold(merged_settings)
          filter_keys(merged_settings)

          apply_feature_gates(merged_settings, connect_reply, existing_config)

          # The value under this key is a hash mapping transaction name strings
          # to apdex_t values. We don't want the nested hash to be flattened
          # as part of the call to super below, so it skips going through
          # merged_settings.
          self[:web_transactions_apdex] = connect_reply['web_transactions_apdex']

          # This causes keys in merged_settings to be symbolized and flattened
          super(merged_settings)
        end

        def merge_top_level_keys(merged_settings, connect_reply)
          TOP_LEVEL_KEYS.each do |key_name|
            if connect_reply[key_name]
              merged_settings[key_name] = connect_reply[key_name]
            end
          end
        end

        def merge_agent_config_hash(merged_settings, connect_reply)
          if connect_reply['agent_config']
            merged_settings.merge!(connect_reply['agent_config'])
          end
        end

        def fix_transaction_threshold(merged_settings)
          # when value is "apdex_f" remove the config and defer to default
          if merged_settings['transaction_tracer.transaction_threshold'] =~ /apdex_f/i
            merged_settings.delete('transaction_tracer.transaction_threshold')
          end
        end

        def filter_keys(merged_settings)
          merged_settings.delete_if do |key, _|
            setting_spec = DEFAULTS[key.to_sym]
            if setting_spec
              if setting_spec[:allowed_from_server]
                false # it's allowed, so don't delete it
              else
                NewRelic::Agent.logger.warn("Ignoring server-sent config for '#{key}' - this setting cannot be set from the server")
                true # delete it
              end
            else
              NewRelic::Agent.logger.debug("Ignoring unrecognized config key from server: '#{key}'")
              true
            end
          end
        end

        # These feature gates are not intended to be bullet-proof, but only to
        # avoid the overhead of collecting and transmitting additional data if
        # the user's subscription level precludes its use. The server is the
        # ultimate authority regarding subscription levels, so we expect it to
        # do the real enforcement there.
        def apply_feature_gates(merged_settings, connect_reply, existing_config)
          gated_features = {
            'transaction_tracer.enabled'     => 'collect_traces',
            'slow_sql.enabled'               => 'collect_traces',
            'error_collector.enabled'        => 'collect_errors',
            'analytics_events.enabled'       => 'collect_analytics_events',
            'custom_insights_events.enabled' => 'collect_custom_events',
            'error_collector.capture_events' => 'collect_error_events'
          }
          gated_features.each do |config_key, gate_key|
            if connect_reply.has_key?(gate_key)
              allowed_by_server = connect_reply[gate_key]
              requested_value   = ungated_value(config_key, merged_settings, existing_config)
              effective_value   = (allowed_by_server && requested_value)
              merged_settings[config_key] = effective_value
            end
          end
        end

        def ungated_value(key, merged_settings, existing_config)
          merged_settings.has_key?(key) ? merged_settings[key] : existing_config[key.to_sym]
        end
      end
    end
  end
end
