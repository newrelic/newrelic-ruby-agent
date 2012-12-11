require 'test/unit'
class IntentionalFail < Test::Unit::TestCase

  # This test suite is provided to facilitate testing that build scripts (e.g.
  # rake test) return the correct exit codes when tests fail.
  def test_fail
    assert false
  end

end
