# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

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

        # ---

        def test_generate_expected_vendors_hash_when_expected_env_vars_present
          with_pcf_env "CF_INSTANCE_GUID" => "fd326c0e-847e-47a1-65cc-45f6",
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
          with_pcf_env "CF_INSTANCE_GUID" => "**fd326c0e-847e-47a1-65cc-45f6**",
                       "CF_INSTANCE_IP" => "10.10.149.48",
                       "MEMORY_LIMIT"   => "1024m" do

            refute @vendor.detect
          end
        end

        def test_fails_when_required_value_is_missing
          with_pcf_env "CF_INSTANCE_GUID" => "fd326c0e-847e-47a1-65cc-45f6",
                       "CF_INSTANCE_IP" => "10.10.149.48" do

            refute @vendor.detect
          end
        end

        # ---

        def with_pcf_env vars, &blk
          vars.each_pair { |k,v| ENV[k] = v }
          blk.call
          vars.keys.each { |k| ENV.delete k }
        end

        # ---

        load_cross_agent_test("utilization_vendor_specific/pcf").each do |test_case|
          test_case = symbolize_keys_in_object test_case

          define_method("test_#{test_case[:testname]}".gsub(" ", "_")) do
            timeout = false
            pcf_env = test_case[:env_vars].reduce({}) do |h,(k,v)|
              h[k.to_s] = v[:response] if v[:response]
              timeout = v[:timeout]
              h
            end

            # TravisCI may run these tests in a docker environment, which means we get an unexpected docker
            # id in the vendors hash.
            with_config :'utilization.detect_docker' => false do
              with_pcf_env pcf_env do
                detection = @vendor.detect

                expected = test_case[:expected_vendors_hash].nil? ? {pcf: {}} : test_case[:expected_vendors_hash]
                assert_equal expected, {pcf: @vendor.metadata}

                if test_case[:expected_metrics]
                  test_case[:expected_metrics].each do |metric,v|
                    if v[:call_count] == 0
                      if timeout
                        refute detection, '@vendor.detect should have returned false'
                      else
                        assert detection, '@vendor.detect should have returned truthy'
                      end
                      assert_metrics_not_recorded [metric.to_s]
                    else
                      refute detection, '@vendor.detect should have returned false'
                      assert_metrics_recorded [metric.to_s]
                    end
                  end
                end
              end
            end
          end

        end
      end
    end
  end
end
