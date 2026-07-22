# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'uri'

module NewRelic
  module Agent
    module ContinuousProfiling
      # Placeholder OTLP destination resolution: the real mechanism (e.g. via the connect
      # response) is undecided, so this resolves from local config only, isolated here so
      # swapping in the real mechanism later only touches this file.
      module OtlpEndpoint
        def self.uri
          URI::HTTPS.build(
            host: NewRelic::Agent.config[:'continuous_profiler.otlp_endpoint.host'],
            port: NewRelic::Agent.config[:'continuous_profiler.otlp_endpoint.port'],
            path: NewRelic::Agent.config[:'continuous_profiler.otlp_endpoint.path']
          )
        end
      end
    end
  end
end
