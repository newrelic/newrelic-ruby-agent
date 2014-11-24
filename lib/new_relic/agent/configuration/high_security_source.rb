# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/configuration'

module NewRelic
  module Agent
    module Configuration
      class HighSecuritySource < DottedHash
        def initialize(local_settings)
          super({
            :ssl => true,

            :capture_params           => false,
            :'resque.capture_params'  => false,
            :'sidekiq.capture_params' => false,

            # These aren't strictly necessary as add_custom_parameters is
            # directly responsible for ignoring incoming param, but we disallow
            # attributes by these settings just to be safe
            :'transaction_tracer.capture_attributes' => false,
            :'error_collector.capture_attributes'    => false,
            :'browser_monitoring.capture_attributes' => false,
            :'analytics_events.capture_attributes'   => false,

            :'transaction_tracer.record_sql' => record_sql_setting(local_settings, :'transaction_tracer.record_sql'),
            :'slow_sql.record_sql'           => record_sql_setting(local_settings, :'slow_sql.record_sql'),
            :'mongo.obfuscate_queries'       => true,

            :'custom_insights_events.enabled'   => false,
            :'strip_exception_messages.enabled' => true
          })
        end

        OFF = "off".freeze
        RAW = "raw".freeze
        OBFUSCATED = "obfuscated".freeze

        SET_TO_OBFUSCATED = [RAW, OBFUSCATED]

        def record_sql_setting(local_settings, key)
          original_value  = local_settings[key]
          result = if SET_TO_OBFUSCATED.include?(original_value)
            OBFUSCATED
          else
            OFF
          end

          if result != original_value
            NewRelic::Agent.logger.info("Disabling setting #{key}='#{original_value}' because high security mode is enabled. Value will be '#{result}'")
          end

          result
        end
      end
    end
  end
end
