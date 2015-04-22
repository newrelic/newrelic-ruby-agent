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
end