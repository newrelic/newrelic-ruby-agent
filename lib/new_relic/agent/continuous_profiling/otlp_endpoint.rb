# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'uri'

module NewRelic
  module Agent
    module ContinuousProfiling
      # Resolves the destination for continuous profiling's OTLP export. The real mechanism
      # for locating this endpoint (e.g. via the connect response, the way the OTLP
      # Metrics/Traces/Logs bridges do for other signals) is undecided -- this is a
      # placeholder resolving from local config only, isolated here so swapping in the real
      # mechanism later only touches this file.
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
