# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Configuration
      module EventData

        extend self

        EVENT_DATA_CONFIG_KEY_MAPPING = {
          :analytic_event_data => :'analytics_events.max_samples_stored',
          :custom_event_data => :'custom_insights_events.max_samples_stored',
          :error_event_data => :'error_collector.max_event_samples_stored'
        }

        def from_config(config)
          {:harvest_limits => EVENT_DATA_CONFIG_KEY_MAPPING.inject({}) do
            |event_data, (event_data_key, config_key)|
              event_data[event_data_key] = config[config_key]
              event_data
            end
          }
        end

        def to_config_hash(connect_reply)
          config_hash = EVENT_DATA_CONFIG_KEY_MAPPING.inject({}) do 
            |event_data, (event_data_key, config_key)|
              event_data[config_key] = connect_reply['event_data']['harvest_limits'][event_data_key.to_s]
              event_data
            end
          config_hash[:event_report_period] = connect_reply['event_data']['report_period_ms'] / 1000
          config_hash
        end
      end
    end
  end
end