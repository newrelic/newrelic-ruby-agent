# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require 'test/unit'
class ATest < Test::Unit::TestCase
  def test_timetrap_is_loaded
    assert Timetrap
  end

  def test_haml_is_not_loaded
    assert !defined?(Haml)
  end
end
