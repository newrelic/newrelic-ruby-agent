require File.expand_path(File.join(File.dirname(__FILE__),'..','test_helper'))
require 'new_relic/coerce'

class CoerceTest < Test::Unit::TestCase
  def test_int_coerce
    assert_equal 1, NewRelic::Coerce.int(1)
    assert_equal 1, NewRelic::Coerce.int("1")
    assert_equal 1, NewRelic::Coerce.int(1.0)
    assert_equal 1, NewRelic::Coerce.int(Rational(1, 1))
    assert_equal 0, NewRelic::Coerce.int("invalid")
    assert_equal 0, NewRelic::Coerce.int(nil)

    # http://ruby-doc.org/core-1.8.7/Symbol.html#method-i-to_i
    assert_equal 0, NewRelic::Coerce.int(:wat) unless RUBY_VERSION < '1.9'
  end

  def test_int_coerce_logs_with_context
    expects_logging(:warn, includes("HERE"), anything)
    NewRelic::Coerce.int("not valid", "HERE")
  end


  def test_float_coerce
    assert_equal 1.0, NewRelic::Coerce.float(1.0)
    assert_equal 1.0, NewRelic::Coerce.float("1.0")
    assert_equal 1.0, NewRelic::Coerce.float(1)
    assert_equal 1.0, NewRelic::Coerce.float(Rational(1, 1))
    assert_equal 0.0, NewRelic::Coerce.float("invalid")
    assert_equal 0.0, NewRelic::Coerce.float(nil)
    assert_equal 0.0, NewRelic::Coerce.float(:symbols_are_fun)
  end

  def test_float_coerce_logs_with_context
    expects_logging(:warn, includes("HERE"), anything)
    NewRelic::Coerce.float("not valid", "HERE")
  end


  def test_string_coerce
    assert_equal "1",      NewRelic::Coerce.string(1)
    assert_equal "1.0",    NewRelic::Coerce.string(1.0)
    assert_equal "string", NewRelic::Coerce.string("string")
    assert_equal "1/100",  NewRelic::Coerce.string(Rational(1, 100))
    assert_equal "yeah",   NewRelic::Coerce.string(:yeah)
    assert_equal "",       NewRelic::Coerce.string(nil)
    assert_equal "",       NewRelic::Coerce.string(Unstringable.new)
  end

  def test_string_coerce_logs_with_context
    expects_logging(:warn, includes("HERE"), anything)
    NewRelic::Coerce.string(Unstringable.new, "HERE")
  end

  class Unstringable
    undef :to_s
  end
end
