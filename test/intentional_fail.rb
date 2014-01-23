# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class IntentionalFail < Minitest::Test

  # This test suite is provided to facilitate testing that build scripts (e.g.
  # rake test) return the correct exit codes when tests fail.
  def test_fail
    assert false
  end

end
