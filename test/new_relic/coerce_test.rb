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

    # http://ruby-doc.org/core-1.8.7/Symbol.html#method-i-to_i
    assert_equal 0, int(:wat) unless RUBY_VERSION < '1.9'
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
    assert_equal nil, int_or_nil("invalid")
    assert_equal nil, int_or_nil(nil)
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
    assert_equal nil,      string(nil)
    assert_equal "",       string(Unstringable.new)
  end

  def test_string_coerce_logs_with_context
    expects_logging(:warn, all_of(includes("HERE"), includes("String")), anything)
    string(Unstringable.new, "HERE")
  end

  def test_event_params_coerce_returns_empty_hash_when_non_hash_is_passed
    assert_equal({}, event_params([]))
    assert_equal({}, event_params(''))
    assert_equal({}, event_params(1))
    assert_equal({}, event_params(nil))
    assert_equal({}, event_params(self.class))
  end

  def test_event_params_coerce_converts_hash_keys_to_strings
    assert_equal(
      {'foo' => 1, 'bar' => 2, '3' => 3},
      event_params({:foo => 1, 'bar' => 2, 3 => 3})
    )
  end

  def test_event_params_coerce_only_allow_values_that_are_strings_symbols_floats_or_ints_or_bools
    assert_equal(
      {
        'foo'    => 1.0,
        'bar'    => 2,
        'bang'   => 'woot',
        'ok'     => 'dokey',
        'truthy' => true,
        'falsy'  => false
      },
      event_params(
        {
          'foo'    => 1.0,
          'bar'    => 2,
          'bang'   => 'woot',
          'ok'     => :dokey,
          'bad'    => [],
          'worse'  => {},
          'nope'   => Rational(1),
          'truthy' => true,
          'falsy'  => false
        }
      )
    )
  end

  def test_event_params_turns_nan_or_infinity_into_null
    assert_equal(
      {
        'nan'  => nil,
        'inf'  => nil,
        'ninf' => nil
      },
      event_params(
        {
          # Ruby 1.8.7 doesn't have Float::NAN, INFINITY so we have to hack it
          'nan'  => 0.0  / 0.0,
          'inf'  => 1.0  / 0.0,
          'ninf' => -1.0 / 0.0
        }
      )
    )
  end

  class Unstringable
    undef :to_s
  end
end
