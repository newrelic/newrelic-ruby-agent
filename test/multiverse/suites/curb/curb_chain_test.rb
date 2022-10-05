# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'curb'
require 'newrelic_rpm'

class CurbChainTest < Minitest::Test
  def test_instrument_bang
    assert_equal :perform, ::NewRelic::Agent::Instrumentation::Curb::Chain.instrument!
  end
end
