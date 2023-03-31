# frozen_string_literal: true

# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

if NewRelic::Agent::Instrumentation::RackHelpers.puma_rack_version_supported?

  require 'puma/rack/urlmap'

  class PumaRackURLMapTest < Minitest::Test
    include MultiverseHelpers

    def test_url_map_generation_is_enhanced_with_tracing
      pairs = {'/' => 'one',
               '/another' => 'another'}
      mapping = pairs.each_with_object({}) { |(k, v), h| h[k] = proc { v } }
      map = Puma::Rack::URLMap.new(mapping)
      pairs.each do |k, v|
        env = {'PATH_INFO' => k, 'SCRIPT_NAME' => 'Eagle Fang'}
        result = map.call(env)
        # confirm basic mapping functionality still works as expected
        assert_equal v, result
        # confirm that we've enhanced the mapping experience
        assert env['newrelic.transaction_started']
      end
    end
  end

end
