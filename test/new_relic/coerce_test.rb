# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','test_helper'))
require 'new_relic/coerce'

class CoerceTest < Minitest::Test

  include NewRelic::Coerce

  def test_int_coerce
    assert_equal 1, int(1)
    assert_equal 1, int("1")
    assert_equal 1, int(1.0)
    assert_equal 1, int(Rational(1, 1))
    assert_equal 0, int("invalid")
    assert_equal 0, int(nil)
    assert_equal 0, int(:wat)
  end

  def test_int_coerce_logs
    expects_logging(:warn, Not(includes("context")), any_parameters)
    int("not valid")
  end

  def test_int_coerce_logs_with_context
    expects_logging(:warn, all_of(includes("HERE"), includes("Integer")), anything)
    int("not valid", "HERE")
  end

  def test_int_coerce_or_nil
    assert_equal 1, int_or_nil(1)
    assert_equal 1, int_or_nil("1")
    assert_equal 1, int_or_nil(1.0)
    assert_equal 1, int_or_nil(Rational(1, 1))
    assert_nil int_or_nil("invalid")
    assert_nil int_or_nil(nil)
  end

  def test_int_or_nil_coerce_logs_with_context
    expects_logging(:warn, all_of(includes("HERE"), includes("Integer")), anything)
    int_or_nil("not valid", "HERE")
  end

  def test_float_coerce
    assert_equal 1.0, float(1.0)
    assert_equal 1.0, float("1.0")
    assert_equal 1.0, float(1)
    assert_equal 1.0, float(Rational(1, 1))
    assert_equal 0.0, float("invalid")
    assert_equal 0.0, float(nil)
    assert_equal 0.0, float(:symbols_are_fun)
  end

  def test_float_coerce_logs_with_context
    expects_logging(:warn, all_of(includes("HERE"), includes("Float")), anything)
    float("not valid", "HERE")
  end

  def test_float_coerce_with_infinite_value_logs_and_returns_0_0
    expects_logging(:warn, all_of(includes("TestingInfinity"), includes("Float"), includes("'Infinity'")), anything)
    infinity = 1337807.0/0.0
    result = float(infinity, "TestingInfinity")
    assert_equal 0.0, result
  end

  def test_float_coerce_with_nan_value_logs_and_returns_0_0
    expects_logging(:warn, all_of(includes("TestingNaN"), includes("Float"), includes("'NaN'")), anything)
    nan = 0.0/0.0
    result = float(nan, "TestingNaN")
    assert_equal 0.0, result
  end

  def test_string_coerce
    assert_equal "1",      string(1)
    assert_equal "1.0",    string(1.0)
    assert_equal "string", string("string")
    assert_equal "1/100",  string(Rational(1, 100))
    assert_equal "yeah",   string(:yeah)
    assert_nil      string(nil)
    assert_equal "",       string(Unstringable.new)
  end

  def test_int!
    assert_equal 120, int!('120')
  end

  def test_float!
    assert_equal 1.23456, float!('1.23456')
  end

  def test_boolean_int!
    assert_equal 1, boolean_int!('1')
    assert_equal 0, boolean_int!('0')
    assert_equal 0, boolean_int!('somethignunexpected')
  end

  def test_value_or_nil
    assert_nil value_or_nil('')
    assert_nil value_or_nil(nil)
    assert_equal 'not_nil', value_or_nil('not_nil')
  end

  def test_string_coerce_logs_with_context
    expects_logging(:warn, all_of(includes("HERE"), includes("String")), anything)
    string(Unstringable.new, "HERE")
  end

  class Unstringable
    undef :to_s
  end
end
