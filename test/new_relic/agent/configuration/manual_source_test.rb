# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

module NewRelic::Agent::Configuration
  class ManualSourceTest < Minitest::Test
    def test_prepopulates_nested_keys
      source = ManualSource.new({ :outer => { :inner => "stuff" } })
      expected = {
        :outer => { :inner => "stuff" },
        :'outer.inner' => "stuff"
      }
      assert_equal(expected, source)
    end
  end
end
