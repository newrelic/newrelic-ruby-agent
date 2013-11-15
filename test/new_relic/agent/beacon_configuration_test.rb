# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require "new_relic/agent/beacon_configuration"

class NewRelic::Agent::BeaconConfigurationTest < Test::Unit::TestCase
  def test_initialize_basic
    with_config(:application_id => 'an application id',
                :beacon => 'beacon', :'rum.enabled' => true) do
      bc = NewRelic::Agent::BeaconConfiguration.new
      assert_equal true, bc.enabled?
    end
  end

  def test_initialize_with_real_data
    with_config(:browser_key => 'a key', :application_id => 'an application id',
                :beacon => 'beacon', :'rum.enabled' => true) do
      bc = NewRelic::Agent::BeaconConfiguration.new
      assert bc.enabled?
    end
  end

  ARRAY_OF_A = [97] * 40

  def test_license_bytes
    with_config(:license_key => 'a' * 40) do
      bc = NewRelic::Agent::BeaconConfiguration.new
      assert_equal(ARRAY_OF_A, bc.license_bytes)
    end
  end

  def test_license_bytes_are_memoized
    with_config(:license_key => 'a' * 40) do
      bc = NewRelic::Agent::BeaconConfiguration.new
      assert_equal(ARRAY_OF_A, bc.license_bytes)

      NewRelic::Agent.config.apply_config(:license_key => 'b' * 40)
      assert_equal(ARRAY_OF_A, bc.license_bytes)
    end
  end

end
