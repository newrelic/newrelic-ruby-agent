# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../../test_helper', __FILE__)
require 'new_relic/agent/utilization/pcf'

module NewRelic
  module Agent
    module Utilization
      class PCFTest < Minitest::Test
        def setup
          @vendor = PCF.new
        end

        def teardown
          NewRelic::Agent.drop_buffered_data
        end

        def test_generate_expected_vendors_hash_when_expected_env_vars_present
          with_env "CF_INSTANCE_GUID" => "fd326c0e-847e-47a1-65cc-45f6",
                   "CF_INSTANCE_IP" => "10.10.149.48",
                   "MEMORY_LIMIT"   => "1024m" do

            expected = {
              :cf_instance_guid => "fd326c0e-847e-47a1-65cc-45f6",
              :cf_instance_ip => "10.10.149.48",
              :memory_limit   => "1024m"
            }

            assert @vendor.detect
            assert_equal expected, @vendor.metadata
          end
        end

        def test_fails_when_expected_value_has_invalid_chars
          with_env "CF_INSTANCE_GUID" => "**fd326c0e-847e-47a1-65cc-45f6**",
                   "CF_INSTANCE_IP" => "10.10.149.48",
                   "MEMORY_LIMIT"   => "1024m" do

            refute @vendor.detect
          end
        end

        def test_fails_when_required_value_is_missing
          with_env "CF_INSTANCE_GUID" => "fd326c0e-847e-47a1-65cc-45f6",
                   "CF_INSTANCE_IP" => "10.10.149.48" do

            refute @vendor.detect
          end
        end

        def with_env vars, &blk
          vars.each_pair { |k,v| ENV[k] = v }
          blk.call
          vars.keys.each { |k| ENV.delete k }
        end
      end
    end
  end
end
