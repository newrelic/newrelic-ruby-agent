require 'test/unit'
class BTest < Test::Unit::TestCase
  def test_timetrap_is_not_loaded
    assert !defined?(Timetrap)
  end

  def test_haml_is_loaded
    assert Haml
  end
end

