# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic
  module Agent
    module Configuration
      module EventHarvestConfig
        extend self

        EVENT_HARVEST_CONFIG_KEY_MAPPING = {
          analytic_event_data: :'analytics_events.max_samples_stored',
          custom_event_data: :'custom_insights_events.max_samples_stored',
          error_event_data: :'error_collector.max_event_samples_stored'
        }

        def from_config(config)
          { harvest_limits: EVENT_HARVEST_CONFIG_KEY_MAPPING.merge(
            span_event_data: :'span_events.max_samples_stored'
          ).each_with_object({}) do |(connect_payload_key, config_key), connect_payload|
                              connect_payload[connect_payload_key] = config[config_key]
                            end }
        end

        def to_config_hash(connect_reply)
          event_harvest_interval = connect_reply['event_harvest_config']['report_period_ms'] / 1000
          config_hash = transform_event_harvest_config_keys(connect_reply, event_harvest_interval)
          config_hash[:event_report_period] = event_harvest_interval
          transform_span_event_harvest_config(config_hash, connect_reply)
        end

        private

        def transform_event_harvest_config_keys(connect_reply, event_harvest_interval)
          EVENT_HARVEST_CONFIG_KEY_MAPPING.each_with_object({}) do |(connect_payload_key, config_key), event_harvest_config|
            unless harvest_limit = connect_reply['event_harvest_config']['harvest_limits'][connect_payload_key.to_s]
              next
            end

            event_harvest_config[config_key] = harvest_limit
            report_period_key = :"event_report_period.#{connect_payload_key}"
            event_harvest_config[report_period_key] = event_harvest_interval
          end
        end

        def transform_span_event_harvest_config(config_hash, connect_reply)
          if span_harvest = connect_reply['span_event_harvest_config']
            if span_harvest['harvest_limit']
              config_hash[:'span_events.max_samples_stored'] =
                span_harvest['harvest_limit']
            end
            if span_harvest['report_period_ms']
              config_hash[:'event_report_period.span_event_data'] =
                span_harvest['report_period_ms']
            end
          end

          config_hash
        end
      end
    end
  end
end
