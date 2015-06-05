# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..','test_helper'))
require 'new_relic/agent/attribute_processing'

class AttributeProcessingTest < Minitest::Test
  def test_flatten_and_coerce_handles_nested_hashes
    params = {"user" =>
      {"addresses" =>
        [
          {"street" => "123 Street", "city" => "City", "state" => "ST", "zip" => "12345"},
          {"street" => "123 Blvd", "city" => "City2", "state" => "ST2", "zip" => "54321"}
        ]
      }
    }

    expected = {
      "request.parameters.user.addresses.0.street" => "123 Street",
      "request.parameters.user.addresses.0.city"   => "City",
      "request.parameters.user.addresses.0.state"  => "ST",
      "request.parameters.user.addresses.0.zip"    => "12345",
      "request.parameters.user.addresses.1.street" => "123 Blvd",
      "request.parameters.user.addresses.1.city"   => "City2",
      "request.parameters.user.addresses.1.state"  => "ST2",
      "request.parameters.user.addresses.1.zip"    => "54321"
    }

    actual = NewRelic::Agent::AttributeProcessing.flatten_and_coerce(params, 'request.parameters')

    assert_equal(expected, actual)
  end

  def test_flatten_and_coerce_coerces_values
    params = {
      "v1" => Class.new,
      "v2" => :symbol,
      "v3" => 1.01
    }

    expected = {
      "request.parameters.v1" => "#<Class>",
      "request.parameters.v2" => "symbol",
      "request.parameters.v3" => 1.01
    }

    actual = NewRelic::Agent::AttributeProcessing.flatten_and_coerce(params, 'request.parameters')

    assert_equal(expected, actual)
  end

  def test_prefix_optional_for_flatten_and_coerce
    params = {:foo => {:bar => ["v1", "v2"]}}

    expected = {
      "foo.bar.0" => "v1",
      "foo.bar.1" => "v2"
    }

    actual = NewRelic::Agent::AttributeProcessing.flatten_and_coerce(params)

    assert_equal(expected, actual)
  end

  def test_prefix_optional_for_flatten_and_coerce_with_initial_array_argument
    params = [:foo => {:bar => ["v1", "v2"]}]

    expected = {
      "0.foo.bar.0" => "v1",
      "0.foo.bar.1" => "v2"
    }

    actual = NewRelic::Agent::AttributeProcessing.flatten_and_coerce(params)

    assert_equal(expected, actual)
  end

  def test_flatten_and_coerce_replaces_empty_hash_with_string_representation
    params = {:foo => {:bar => {}}}

    expected = { "foo.bar" => "{}" }

    actual = NewRelic::Agent::AttributeProcessing.flatten_and_coerce(params)

    assert_equal(expected, actual)
  end

  def test_flatten_and_coerce_replaces_empty_array_with_string_representation
    params = {:foo => {:bar => []}}

    expected = { "foo.bar" => "[]" }

    actual = NewRelic::Agent::AttributeProcessing.flatten_and_coerce(params)

    assert_equal(expected, actual)
  end

  def test_flatten_and_coerce_coerce_handles_values_mixed_and_complex_types_properly
    assert_equal(
      {
        'foo'    => 1.0,
        'bar'    => 2,
        'bang'   => 'woot',
        'ok'     => 'dokey',
        'yes'    => '[]',
        'yup'    => '{}',
        'yayuh'  => '#<Rational>',
        'truthy' => true,
        'falsy'  => false
      },
      NewRelic::Agent::AttributeProcessing.flatten_and_coerce(
        {
          'foo'    => 1.0,
          'bar'    => 2,
          'bang'   => 'woot',
          'ok'     => :dokey,
          'yes'    => [],
          'yup'  => {},
          'yayuh'   => Rational(1),
          'truthy' => true,
          'falsy'  => false
        }
      )
    )
  end

  def test_flatten_and_coerce_turns_nan_or_infinity_into_null_and_then_dropped
    assert_equal(
      {
      },
      NewRelic::Agent::AttributeProcessing.flatten_and_coerce(
        {
          # Ruby 1.8.7 doesn't have Float::NAN, INFINITY so we have to hack it
          'nan'  => 0.0  / 0.0,
          'inf'  => 1.0  / 0.0,
          'ninf' => -1.0 / 0.0
        }
      )
    )
  end

  def test_flatten_and_coerce_logs_warning_with_unexpected_arguments
    expects_logging(:warn, all_of(includes("Unexpected object"), includes("flatten_and_coerce")))
    NewRelic::Agent::AttributeProcessing.flatten_and_coerce(Object.new)
  end

  def test_flatten_and_coerce_calls_a_block_key_and_value_when_provided
    params = {:foo => {:bar => ["qux", "quux"]}}
    yielded = {}

    NewRelic::Agent::AttributeProcessing.flatten_and_coerce(params) { |k, v| yielded[k] = v}

    expected = {"foo.bar.0" => "qux", "foo.bar.1" => "quux"}
    assert_equal expected, yielded
  end

  def test_flatten_and_coerce_leaves_nils_alone
    params   = { :referer => nil }
    expected = { }

    result = NewRelic::Agent::AttributeProcessing.flatten_and_coerce(params)
    assert_equal expected, result
  end
end
