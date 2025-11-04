# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/transaction'
require 'new_relic/agent/transaction/sampling_decision'

module NewRelic
  module Agent
    class Transaction
      class SamplingDecisionTest < Minitest::Test
        include SamplingDecision

        def setup
          @config = {
            :'distributed_tracing.enabled' => true,
            :account_id => '190',
            :primary_application_id => '46954',
            :trusted_account_key => 'trust_this!'
          }
          NewRelic::Agent.instance.stubs(:connected?).returns(true)
          NewRelic::Agent.config.add_config_for_testing(@config)
        end

        def teardown
          NewRelic::Agent.config.remove_config(@config)
          NewRelic::Agent.config.reset_to_defaults
          NewRelic::Agent.drop_buffered_data
        end

        def test_determine_root_sampling_with_default_sampler_sampled
          NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)

          transaction = in_transaction('test_txn') do |txn|
            txn
          end

          with_config(:'distributed_tracing.sampler.root' => 'default') do
            result = SamplingDecision.determine_root_sampling(transaction)

            assert result[:sampled]
            assert_in_delta 1.5, result[:priority], 0.5, 'Priority should be between 1.0 and 2.0 for sampled adaptive'
          end
        end

        def test_determine_root_sampling_with_default_sampler_not_sampled
          NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(false)

          transaction = in_transaction('test_txn') do |txn|
            txn
          end

          with_config(:'distributed_tracing.sampler.root' => 'default') do
            result = SamplingDecision.determine_root_sampling(transaction)

            refute result[:sampled]
            assert_in_delta 0.5, result[:priority], 0.5, 'Priority should be between 0.0 and 1.0 for not sampled adaptive'
          end
        end

        def test_determine_root_sampling_with_adaptive_sampler_sampled
          NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)

          transaction = in_transaction('test_txn') do |txn|
            txn
          end

          with_config(:'distributed_tracing.sampler.root' => 'adaptive') do
            result = SamplingDecision.determine_root_sampling(transaction)

            assert result[:sampled]
            assert_in_delta 1.5, result[:priority], 0.5
          end
        end

        def test_determine_root_sampling_with_always_on_sampler
          transaction = in_transaction('test_txn') do |txn|
            txn
          end

          with_config(:'distributed_tracing.sampler.root' => 'always_on') do
            result = SamplingDecision.determine_root_sampling(transaction)

            assert result[:sampled]
            assert_equal 2.0, result[:priority] # rubocop: disable Minitest/AssertInDelta
          end
        end

        def test_determine_root_sampling_with_always_off_sampler
          transaction = in_transaction('test_txn') do |txn|
            txn
          end

          with_config(:'distributed_tracing.sampler.root' => 'always_off') do
            result = SamplingDecision.determine_root_sampling(transaction)

            refute result[:sampled]
            assert_equal 0, result[:priority]
          end
        end

        def test_determine_root_sampling_with_trace_id_ratio_based_sampler_ratio_one
          transaction = in_transaction('test_txn') do |txn|
            txn
          end

          with_config(
            :'distributed_tracing.sampler.root' => 'trace_id_ratio_based',
            :'distributed_tracing.sampler.root.trace_id_ratio_based.ratio' => 1.0
          ) do
            result = SamplingDecision.determine_root_sampling(transaction)

            assert result[:sampled]
            assert_in_delta(2.0, result[:priority])
          end
        end

        def test_determine_root_sampling_with_trace_id_ratio_based_sampler_ratio_zero
          transaction = in_transaction('test_txn') do |txn|
            txn
          end

          with_config(
            :'distributed_tracing.sampler.root' => 'trace_id_ratio_based',
            :'distributed_tracing.sampler.root.trace_id_ratio_based.ratio' => 0.0
          ) do
            result = SamplingDecision.determine_root_sampling(transaction)

            refute result[:sampled]
            assert_equal 0, result[:priority]
          end
        end

        def test_determine_root_sampling_with_trace_id_ratio_based_sampler_ratio_half
          transaction = in_transaction('test_txn') do |txn|
            txn
          end

          with_config(
            :'distributed_tracing.sampler.root' => 'trace_id_ratio_based',
            :'distributed_tracing.sampler.root.trace_id_ratio_based.ratio' => 0.5
          ) do
            result = SamplingDecision.determine_root_sampling(transaction)

            assert_includes [true, false], result[:sampled], 'Sampled should be boolean'
            assert_equal(result[:sampled] ? 2.0 : 0, result[:priority])
          end
        end

        def test_determine_root_sampling_with_unknown_sampler_falls_back_to_adaptive
          NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)

          transaction = in_transaction('test_txn') do |txn|
            txn
          end

          with_config(:'distributed_tracing.sampler.root' => 'unknown_sampler') do
            result = SamplingDecision.determine_root_sampling(transaction)

            assert result[:sampled]
            assert_in_delta 1.5, result[:priority], 0.5
          end
        end

        def test_determine_remote_sampling_with_default_sampler_uses_payload
          payload = OpenStruct.new(sampled: true, priority: 1.5)
          trace_id = '12345678901234567890123456789012'

          with_config(:'distributed_tracing.sampler.remote_parent_sampled' => 'default') do
            result = SamplingDecision.determine_remote_sampling(
              NewRelic::Agent.config[:'distributed_tracing.sampler.remote_parent_sampled'],
              NewRelic::Agent.config[:'distributed_tracing.sampler.remote_parent_sampled.trace_id_ratio_based.ratio'],
              trace_id,
              payload
            )

            assert_equal true, result[:sampled] # rubocop:disable Minitest/AssertTruthy
            assert_equal 1.5, result[:priority] # rubocop:disable Minitest/AssertInDelta
          end
        end

        def test_determine_remote_sampling_with_adaptive_sampler_uses_payload
          payload = OpenStruct.new(sampled: false, priority: 0.8)
          trace_id = '12345678901234567890123456789012'

          with_config(:'distributed_tracing.sampler.remote_parent_not_sampled' => 'adaptive') do
            result = SamplingDecision.determine_remote_sampling(
              NewRelic::Agent.config[:'distributed_tracing.sampler.remote_parent_not_sampled'],
              NewRelic::Agent.config[:'distributed_tracing.sampler.remote_parent_not_sampled.trace_id_ratio_based.ratio'],
              trace_id,
              payload
            )

            assert_equal false, result[:sampled] # rubocop:disable Minitest/RefuteFalse
            assert_equal 0.8, result[:priority] # rubocop:disable Minitest/AssertInDelta
          end
        end

        def test_determine_remote_sampling_with_always_on_sampler
          payload = OpenStruct.new(sampled: false, priority: 0.5)
          trace_id = '12345678901234567890123456789012'

          with_config(:'distributed_tracing.sampler.remote_parent_sampled' => 'always_on') do
            result = SamplingDecision.determine_remote_sampling(
              NewRelic::Agent.config[:'distributed_tracing.sampler.remote_parent_sampled'],
              NewRelic::Agent.config[:'distributed_tracing.sampler.remote_parent_sampled.trace_id_ratio_based.ratio'],
              trace_id,
              payload
            )

            assert_equal true, result[:sampled] # rubocop:disable Minitest/AssertTruthy
            assert_equal 2.0, result[:priority] # rubocop:disable Minitest/AssertInDelta
          end
        end

        def test_determine_remote_sampling_with_always_off_sampler
          payload = OpenStruct.new(sampled: true, priority: 1.8)
          trace_id = '12345678901234567890123456789012'

          with_config(:'distributed_tracing.sampler.remote_parent_not_sampled' => 'always_off') do
            result = SamplingDecision.determine_remote_sampling(
              NewRelic::Agent.config[:'distributed_tracing.sampler.remote_parent_not_sampled'],
              NewRelic::Agent.config[:'distributed_tracing.sampler.remote_parent_not_sampled.trace_id_ratio_based.ratio'],
              trace_id,
              payload
            )

            assert_equal false, result[:sampled] # rubocop:disable Minitest/RefuteFalse
            assert_equal 0, result[:priority]
          end
        end

        def test_determine_remote_sampling_with_trace_id_ratio_based_sampler_ratio_one
          payload = OpenStruct.new(sampled: false, priority: 0.5)
          trace_id = '12345678901234567890123456789012'

          with_config(
            :'distributed_tracing.sampler.remote_parent_sampled' => 'trace_id_ratio_based',
            :'distributed_tracing.sampler.remote_parent_sampled.trace_id_ratio_based.ratio' => 1.0
          ) do
            result = SamplingDecision.determine_remote_sampling(
              NewRelic::Agent.config[:'distributed_tracing.sampler.remote_parent_sampled'],
              NewRelic::Agent.config[:'distributed_tracing.sampler.remote_parent_sampled.trace_id_ratio_based.ratio'],
              trace_id,
              payload
            )

            assert_equal true, result[:sampled] # rubocop:disable Minitest/AssertTruthy
            assert_equal 2.0, result[:priority] # rubocop:disable Minitest/AssertInDelta
          end
        end

        def test_determine_remote_sampling_with_trace_id_ratio_based_sampler_ratio_zero
          payload = OpenStruct.new(sampled: true, priority: 1.5)
          trace_id = '12345678901234567890123456789012'

          with_config(
            :'distributed_tracing.sampler.remote_parent_not_sampled' => 'trace_id_ratio_based',
            :'distributed_tracing.sampler.remote_parent_not_sampled.trace_id_ratio_based.ratio' => 0.0
          ) do
            result = SamplingDecision.determine_remote_sampling(
              NewRelic::Agent.config[:'distributed_tracing.sampler.remote_parent_not_sampled'],
              NewRelic::Agent.config[:'distributed_tracing.sampler.remote_parent_not_sampled.trace_id_ratio_based.ratio'],
              trace_id,
              payload
            )

            assert_equal false, result[:sampled] # rubocop:disable Minitest/RefuteFalse
            assert_equal 0, result[:priority]
          end
        end

        def test_determine_remote_sampling_with_unknown_sampler_falls_back_to_payload
          payload = OpenStruct.new(sampled: true, priority: 1.2)
          trace_id = '12345678901234567890123456789012'

          with_config(:'distributed_tracing.sampler.remote_parent_sampled' => 'unknown_sampler') do
            result = SamplingDecision.determine_remote_sampling(
              NewRelic::Agent.config[:'distributed_tracing.sampler.remote_parent_sampled'],
              NewRelic::Agent.config[:'distributed_tracing.sampler.remote_parent_sampled.trace_id_ratio_based.ratio'],
              trace_id,
              payload
            )

            assert_equal true, result[:sampled] # rubocop:disable Minitest/AssertTruthy
            assert_equal 1.2, result[:priority] # rubocop:disable Minitest/AssertInDelta
          end
        end

        def test_use_payload_sampling_returns_sampled_and_priority
          payload = OpenStruct.new(sampled: true, priority: 1.75)

          result = SamplingDecision.use_payload_sampling(payload)

          assert_equal true, result[:sampled] # rubocop:disable Minitest/AssertTruthy
          assert_equal 1.75, result[:priority] # rubocop:disable Minitest/AssertInDelta
        end

        def test_use_payload_sampling_with_nil_sampled_returns_empty_hash
          payload = OpenStruct.new(sampled: nil, priority: 1.5)

          result = SamplingDecision.use_payload_sampling(payload)

          assert_empty(result)
        end

        def test_use_payload_sampling_with_sampled_but_no_priority
          payload = OpenStruct.new(sampled: true, priority: nil)

          result = SamplingDecision.use_payload_sampling(payload)

          assert_equal true, result[:sampled] # rubocop:disable Minitest/AssertTruthy
          refute result.key?(:priority)
        end

        def test_calculate_trace_id_ratio_sampled_with_ratio_one_always_returns_true
          trace_id = '12345678901234567890123456789012'

          result = SamplingDecision.calculate_trace_id_ratio_sampled(1.0, trace_id)

          assert result
        end

        def test_calculate_trace_id_ratio_sampled_with_ratio_zero_always_returns_false
          trace_id = '12345678901234567890123456789012'

          result = SamplingDecision.calculate_trace_id_ratio_sampled(0.0, trace_id)

          refute result
        end

        def test_calculate_trace_id_ratio_sampled_uses_trace_id_for_deterministic_result
          trace_id = '12345678901234567890123456789012'
          ratio = 0.5

          result1 = SamplingDecision.calculate_trace_id_ratio_sampled(ratio, trace_id)
          result2 = SamplingDecision.calculate_trace_id_ratio_sampled(ratio, trace_id)

          assert_equal result1, result2, 'Same trace_id should produce same result'
        end

        def test_calculate_trace_id_ratio_sampled_ignores_high_bits_of_trace_id
          # Only the middle 8 bytes (positions 8-15) affect sampling
          # Changing the first 8 or last 16 bytes should not change the result if middle stays same
          trace_id1 = '00000000' + '12345678' + '0000000000000000'
          trace_id2 = 'ffffffff' + '12345678' + 'ffffffffffffffff'
          ratio = 0.5

          result1 = SamplingDecision.calculate_trace_id_ratio_sampled(ratio, trace_id1)
          result2 = SamplingDecision.calculate_trace_id_ratio_sampled(ratio, trace_id2)

          assert_equal result1, result2, 'Only middle 8 bytes should affect sampling'
        end

        def test_calculate_trace_id_ratio_sampled_with_realistic_trace_ids
          # Test with trace IDs that look like actual New Relic generated GUIDs
          # New Relic generates lowercase hex strings (0-9, a-f)
          trace_id_numeric = '12345678' + '90123456' + '78901234567890ab' # Mostly numeric
          trace_id_mixed = 'a1b2c3d4' + 'e5f67890' + '123456789abcdef0' # Mixed hex
          trace_id_letters = 'abcdef01' + '23456789' + 'abcdefabcdefabcd' # More letters
          ratio = 0.5

          # All should be sampled at 0.5 ratio since ASCII values of hex chars
          # (0x30-0x39 for 0-9, 0x61-0x66 for a-f) produce relatively low values
          assert SamplingDecision.calculate_trace_id_ratio_sampled(ratio, trace_id_numeric)
          assert SamplingDecision.calculate_trace_id_ratio_sampled(ratio, trace_id_mixed)
          assert SamplingDecision.calculate_trace_id_ratio_sampled(ratio, trace_id_letters)
        end

        def test_calculate_trace_id_ratio_sampled_edge_cases
          # Test edge cases with leading zeros (which New Relic pads with)
          trace_id_leading_zeros = '00000000' + '00000001' + '0000000000000000'
          trace_id_all_f = 'ffffffff' + 'ffffffff' + 'ffffffffffffffff'

          # Very low ratio - should not sample high values
          refute SamplingDecision.calculate_trace_id_ratio_sampled(0.0000001, trace_id_all_f)

          # High ratio - should sample low values
          assert SamplingDecision.calculate_trace_id_ratio_sampled(0.9999999, trace_id_leading_zeros)
        end

        def test_adaptive_priority_sampled_returns_value_between_one_and_two
          100.times do
            result = SamplingDecision.adaptive_priority(true)

            assert result >= 1.0, "Priority should be >= 1.0, got #{result}"
            assert result <= 2.0, "Priority should be <= 2.0, got #{result}"
          end
        end

        def test_adaptive_priority_not_sampled_returns_value_between_zero_and_one
          100.times do
            result = SamplingDecision.adaptive_priority(false)

            assert result >= 0.0, "Priority should be >= 0.0, got #{result}"
            assert result < 1.0, "Priority should be < 1.0, got #{result}"
          end
        end

        def test_adaptive_priority_rounds_to_six_decimal_places
          result = SamplingDecision.adaptive_priority(true)

          # Check that the result has at most 6 decimal places
          assert_equal result, result.round(6)
        end
      end
    end
  end
end
