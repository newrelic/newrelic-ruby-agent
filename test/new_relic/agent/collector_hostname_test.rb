# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

module NewRelic::Agent
  class CollectorHostname < Minitest::Test

    test_cases = load_cross_agent_test("collector_hostname")

    test_cases.each do |test_case|
      define_method("test_#{test_case['name']}".tr(" ", "_")) do

        # The configuration manager checks the following places to
        # determine the collector host:
        #
        # 1. Explicit configuration option (e.g., newrelic.yml)
        # 2. Implicit in a region-specific license key
        # 3. The default host
        #
        # We'll initialize those same three environments, layered on
        # top of one another.
        #
        explicit_config = {}
        explicit_config[:host] = test_case['override_host'] if test_case['override_host']
        explicit_config = ::NewRelic::Agent::Configuration::DottedHash.new(explicit_config, true)

        implicit_config = { license_key: test_case['key'] }
        implicit_config = ::NewRelic::Agent::Configuration::DottedHash.new(implicit_config, true)

        default_config = ::NewRelic::Agent::Configuration::DefaultSource.new

        with_config default_config do
          with_config explicit_config do
            with_config implicit_config do
              # Bypass the cache so that we don't end up with the host from
              # the previous run of this test case.
              #
              actual_host = ::NewRelic::Agent.config.fetch(:host)

              assert_equal test_case['hostname'], actual_host
            end
          end
        end
      end

    end

  end
end
