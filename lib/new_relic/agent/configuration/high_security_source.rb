# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/configuration'

module NewRelic
  module Agent
    module Configuration
      class HighSecuritySource < DottedHash
        def initialize
          super({
            :ssl => true,

            :capture_params => false,
            :'resque.capture_params'  => false,
            :'sidekiq.capture_params' => false,

            # TODO: Should this allow Yaml to ask for obfuscated instead?
            :'transaction_tracer.record_sql' => 'off',
            :'slow_sql.record_sql'           => 'off',
          })
        end
      end
    end
  end
end
