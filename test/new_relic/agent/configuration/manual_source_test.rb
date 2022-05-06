# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative '../../../test_helper'

module NewRelic::Agent::Configuration
  class ManualSourceTest < Minitest::Test
    def test_prepopulates_nested_keys
      source = ManualSource.new({:outer => {:inner => "stuff"}})
      expected = {
        :outer => {:inner => "stuff"},
        :'outer.inner' => "stuff"
      }
      assert_equal(expected, source)
    end
  end
end
