# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Configuration
      # Maps a subset of OpenTelemetry environment variable configuration to
      # New Relic configuration equivalents. Values are only considered when
      # opentelemetry.enabled is true, so that applications that do not use
      # the OTel bridge are unaffected.
      class OpenTelemetrySource < DottedHash
        OTEL_ENV_MAPPINGS = {
          'OTEL_SERVICE_NAME' => :app_name,
          'OTEL_LOG_LEVEL' => :log_level,
          'OTEL_RESOURCE_ATTRIBUTES' => :labels,
          'OTEL_BSP_MAX_EXPORT_BATCH_SIZE' => :'span_events.max_samples_stored',
          'OTEL_BLRP_MAX_EXPORT_BATCH_SIZE' => :'application_logging.forwarding.max_samples_stored'
        }.freeze

        def initialize
          @otel_values = {}

          OTEL_ENV_MAPPINGS.each do |env_var, config_key|
            raw = ENV[env_var]
            next unless raw

            @otel_values[config_key] = transform(config_key, raw)
          end

          super({})
        end

        def has_key?(key)
          @otel_values.key?(key) && otel_enabled?
        end

        def [](key)
          has_key?(key) ? @otel_values[key] : nil
        end

        private

        def otel_enabled?
          NewRelic::Agent.config[:'opentelemetry.enabled']
        end

        # Convert OTEL env var values to the format expected by NR config keys.
        def transform(config_key, value)
          case config_key
          when :labels then otel_resource_attributes_to_nr_labels(value)
          when :log_level then value.downcase
          else value
          end
        end

        # OTEL_RESOURCE_ATTRIBUTES: "key1=value1,key2=value2"
        # NR labels:                "key1:value1;key2:value2"
        def otel_resource_attributes_to_nr_labels(raw)
          raw.split(',').map { |pair| pair.sub('=', ':') }.join(';')
        end
      end
    end
  end
end
