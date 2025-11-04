# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/transaction'
require 'new_relic/agent/transaction/sampling_decision'

module NewRelic
  module Agent
    class SamplerIntegrationTest < Minitest::Test
      include Transaction::SamplingDecision

      def setup
        @config = {
          :'distributed_tracing.enabled' => true,
          :account_id => '190',
          :primary_application_id => '46954',
          :trusted_account_key => 'trust_this!'
        }
        NewRelic::Agent.instance.stubs(:connected?).returns(true)
        NewRelic::Agent.config.add_config_for_testing(@config)
        # Reset the warning tracking
        NewRelic::Agent::Configuration::SamplerConfigValidator.reset_warnings!
      end

      def teardown
        NewRelic::Agent.config.remove_config(@config)
        NewRelic::Agent.config.reset_to_defaults
        NewRelic::Agent.drop_buffered_data
        # Reset the warning tracking
        NewRelic::Agent::Configuration::SamplerConfigValidator.reset_warnings!
      end

      def test_root_sampler_falls_back_to_default_with_invalid_ratio
        NewRelic::Agent.logger.expects(:warn).with(regexp_matches(/Invalid or missing ratio/)).once

        transaction = in_transaction('test_txn') do |txn|
          txn
        end

        # Adaptive sampler should be used due to fallback
        NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)

        with_config(
          :'distributed_tracing.sampler.root' => 'trace_id_ratio_based',
          :'distributed_tracing.sampler.root.trace_id_ratio_based.ratio' => nil
        ) do
          # The config system should have transformed trace_id_ratio_based to 'default'
          strategy = NewRelic::Agent.config[:'distributed_tracing.sampler.root']

          assert_equal 'default', strategy, "Strategy should fall back to 'default'"

          # SamplingDecision should use adaptive sampler (default behavior)
          result = Transaction::SamplingDecision.determine_root_sampling(transaction)

          assert result[:sampled], 'Should use adaptive sampler'
          assert_in_delta 1.5, result[:priority], 0.5, 'Priority should be adaptive'
        end
      end

      def test_remote_parent_sampled_falls_back_to_payload_with_invalid_ratio
        NewRelic::Agent.logger.expects(:warn).with(regexp_matches(/Invalid or missing ratio/)).once

        payload = OpenStruct.new(sampled: true, priority: 1.7)
        trace_id = '12345678901234567890123456789012'

        with_config(
          :'distributed_tracing.sampler.remote_parent_sampled' => 'trace_id_ratio_based',
          :'distributed_tracing.sampler.remote_parent_sampled.trace_id_ratio_based.ratio' => 1.5 # Invalid: > 1.0
        ) do
          # The config system should have transformed the strategy to 'default'
          strategy = NewRelic::Agent.config[:'distributed_tracing.sampler.remote_parent_sampled']

          assert_equal 'default', strategy, "Strategy should fall back to 'default'"

          # The ratio should have been validated and become nil
          ratio = NewRelic::Agent.config[:'distributed_tracing.sampler.remote_parent_sampled.trace_id_ratio_based.ratio']

          assert_nil ratio, 'Invalid ratio should be transformed to nil'

          # SamplingDecision should use payload (default behavior)
          result = Transaction::SamplingDecision.determine_remote_sampling(
            NewRelic::Agent.config[:'distributed_tracing.sampler.remote_parent_sampled'],
            NewRelic::Agent.config[:'distributed_tracing.sampler.remote_parent_sampled.trace_id_ratio_based.ratio'],
            trace_id,
            payload
          )

          assert_equal true, result[:sampled], 'Should use payload sampled value' # rubocop:disable Minitest/AssertTruthy
          assert_in_delta(1.7, result[:priority], 0.001, 'Should use payload priority')
        end
      end

      def test_valid_ratio_works_end_to_end
        transaction = in_transaction('test_txn') do |txn|
          txn
        end

        with_config(
          :'distributed_tracing.sampler.root' => 'trace_id_ratio_based',
          :'distributed_tracing.sampler.root.trace_id_ratio_based.ratio' => 1.0
        ) do
          # Config should remain trace_id_ratio_based with valid ratio
          strategy = NewRelic::Agent.config[:'distributed_tracing.sampler.root']

          assert_equal 'trace_id_ratio_based', strategy

          ratio = NewRelic::Agent.config[:'distributed_tracing.sampler.root.trace_id_ratio_based.ratio']

          assert_in_delta(1.0, ratio)

          # SamplingDecision should use trace_id_ratio_based sampling
          result = Transaction::SamplingDecision.determine_root_sampling(transaction)

          assert result[:sampled], 'Should be sampled with ratio 1.0'
          assert_in_delta(2.0, result[:priority])
        end
      end

      def test_warning_logged_only_once_across_multiple_config_accesses
        # Reset warnings to ensure clean state
        NewRelic::Agent::Configuration::SamplerConfigValidator.reset_warnings!

        NewRelic::Agent.logger.expects(:warn).with(regexp_matches(/Invalid or missing ratio/)).once

        with_config(
          :'distributed_tracing.sampler.root' => 'trace_id_ratio_based',
          :'distributed_tracing.sampler.root.trace_id_ratio_based.ratio' => nil
        ) do
          # Access the config multiple times to simulate multiple sources
          5.times do
            strategy = NewRelic::Agent.config[:'distributed_tracing.sampler.root']

            assert_equal 'default', strategy
          end
        end
      end

      def test_string_ratio_is_invalid_and_causes_fallback
        NewRelic::Agent.logger.stubs(:warn)

        with_config(
          :'distributed_tracing.sampler.root' => 'trace_id_ratio_based',
          :'distributed_tracing.sampler.root.trace_id_ratio_based.ratio' => '0.5' # String, not Float
        ) do
          # String should be transformed to nil
          ratio = NewRelic::Agent.config[:'distributed_tracing.sampler.root.trace_id_ratio_based.ratio']

          assert_nil ratio, 'String ratio should be transformed to nil'

          # Strategy should fall back to default
          strategy = NewRelic::Agent.config[:'distributed_tracing.sampler.root']

          assert_equal 'default', strategy
        end
      end

      def test_integer_ratio_is_invalid_and_causes_fallback
        NewRelic::Agent.logger.stubs(:warn)

        with_config(
          :'distributed_tracing.sampler.root' => 'trace_id_ratio_based',
          :'distributed_tracing.sampler.root.trace_id_ratio_based.ratio' => 1 # Integer, not Float
        ) do
          # Integer should be transformed to nil
          ratio = NewRelic::Agent.config[:'distributed_tracing.sampler.root.trace_id_ratio_based.ratio']

          assert_nil ratio, 'Integer ratio should be transformed to nil'

          # Strategy should fall back to default
          strategy = NewRelic::Agent.config[:'distributed_tracing.sampler.root']

          assert_equal 'default', strategy
        end
      end

      def test_other_strategies_not_affected_by_invalid_ratio
        # Invalid ratio should not affect non-trace_id_ratio_based strategies

        with_config(
          :'distributed_tracing.sampler.root' => 'always_on',
          :'distributed_tracing.sampler.root.trace_id_ratio_based.ratio' => 1.5 # Invalid, but shouldn't matter
        ) do
          strategy = NewRelic::Agent.config[:'distributed_tracing.sampler.root']

          assert_equal 'always_on', strategy, 'Other strategies should not be affected'
        end

        with_config(
          :'distributed_tracing.sampler.root' => 'adaptive',
          :'distributed_tracing.sampler.root.trace_id_ratio_based.ratio' => nil
        ) do
          strategy = NewRelic::Agent.config[:'distributed_tracing.sampler.root']

          assert_equal 'adaptive', strategy, 'Other strategies should not be affected'
        end
      end
    end
  end
end
