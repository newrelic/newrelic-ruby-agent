# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/continuous_profiling/otlp_endpoint'

module NewRelic::Agent::ContinuousProfiling
  class OtlpEndpointTest < Minitest::Test
    def test_uri_is_built_from_the_placeholder_config_keys
      with_config(
        :'continuous_profiler.otlp_endpoint.host' => 'otlp.example.com',
        :'continuous_profiler.otlp_endpoint.port' => 4318,
        :'continuous_profiler.otlp_endpoint.path' => '/v1/profiles'
      ) do
        uri = OtlpEndpoint.uri

        assert_equal 'https', uri.scheme
        assert_equal 'otlp.example.com', uri.host
        assert_equal 4318, uri.port
        assert_equal '/v1/profiles', uri.path
      end
    end
  end
end
