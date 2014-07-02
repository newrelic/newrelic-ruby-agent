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

            :'transaction_tracer.record_sql' => record_sql_setting(local_settings, :'transaction_tracer.record_sql'),
            :'slow_sql.record_sql'           => record_sql_setting(local_settings, :'slow_sql.record_sql')
          })
        end

        OFF = "off".freeze
        RAW = "raw".freeze
        OBFUSCATED = "obfuscated".freeze

        SET_TO_OBFUSCATED = [RAW, OBFUSCATED]

        def record_sql_setting(local_settings, key)
          if SET_TO_OBFUSCATED.include?(local_settings[key])
            OBFUSCATED
          else
            OFF
          end
        end
      end
    end
  end
end
