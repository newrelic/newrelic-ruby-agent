# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/configuration/default_source'
require 'new_relic/agent/configuration/sampler_config_validator'

module NewRelic::Agent::Configuration
  class SamplerConfigValidatorTest < Minitest::Test
    def setup
      NewRelic::Agent.config.reset_to_defaults
      SamplerConfigValidator.reset_warnings!
    end

    def teardown
      NewRelic::Agent.config.reset_to_defaults
      SamplerConfigValidator.reset_warnings!
    end

    def test_validate_sampling_ratio_accepts_valid_floats_in_range
      assert_in_delta(0.5, SamplerConfigValidator.validate_sampling_ratio(0.5))
      assert_in_delta(0.0, SamplerConfigValidator.validate_sampling_ratio(0.0))
      assert_in_delta(1.0, SamplerConfigValidator.validate_sampling_ratio(1.0))
      assert_in_delta(0.123456, SamplerConfigValidator.validate_sampling_ratio(0.123456))
    end

    def test_validate_sampling_ratio_returns_nil_for_nil_input
      assert_nil SamplerConfigValidator.validate_sampling_ratio(nil)
    end

    def test_validate_sampling_ratio_returns_nil_for_non_float
      assert_nil SamplerConfigValidator.validate_sampling_ratio(0.5.to_s)
      assert_nil SamplerConfigValidator.validate_sampling_ratio(1)
      assert_nil SamplerConfigValidator.validate_sampling_ratio('invalid')
    end

    def test_validate_sampling_ratio_returns_nil_for_out_of_range
      assert_nil SamplerConfigValidator.validate_sampling_ratio(-0.1)
      assert_nil SamplerConfigValidator.validate_sampling_ratio(1.1)
      assert_nil SamplerConfigValidator.validate_sampling_ratio(100.0)
    end

    def test_root_strategy_with_valid_ratio_returns_trace_id_ratio_based
      with_config(:'distributed_tracing.sampler.root.trace_id_ratio_based.ratio' => 0.5) do
        config_value = NewRelic::Agent.config[:'distributed_tracing.sampler.root']

        transform = SamplerConfigValidator.validate_sampler_strategy_with_ratio(
          :'distributed_tracing.sampler.root',
          :'distributed_tracing.sampler.root.trace_id_ratio_based.ratio'
        )
        result = transform.call('trace_id_ratio_based')

        assert_equal 'trace_id_ratio_based', result
      end
    end

    def test_remote_parent_sampled_strategy_with_valid_ratio_returns_trace_id_ratio_based
      with_config(:'distributed_tracing.sampler.remote_parent_sampled.trace_id_ratio_based.ratio' => 0.75) do
        transform = SamplerConfigValidator.validate_sampler_strategy_with_ratio(
          :'distributed_tracing.sampler.remote_parent_sampled',
          :'distributed_tracing.sampler.remote_parent_sampled.trace_id_ratio_based.ratio'
        )
        result = transform.call('trace_id_ratio_based')

        assert_equal 'trace_id_ratio_based', result
      end
    end

    def test_root_strategy_falls_back_to_default_when_ratio_is_nil
      NewRelic::Agent.logger.stubs(:warn)

      with_config(:'distributed_tracing.sampler.root.trace_id_ratio_based.ratio' => nil) do
        transform = SamplerConfigValidator.validate_sampler_strategy_with_ratio(
          :'distributed_tracing.sampler.root',
          :'distributed_tracing.sampler.root.trace_id_ratio_based.ratio'
        )
        result = transform.call('trace_id_ratio_based')

        assert_equal 'adaptive', result
      end
    end

    def test_root_strategy_falls_back_to_adaptive_default_when_ratio_is_out_of_range
      NewRelic::Agent.logger.stubs(:warn)

      with_config(:'distributed_tracing.sampler.root.trace_id_ratio_based.ratio' => 1.5) do
        ratio = NewRelic::Agent.config[:'distributed_tracing.sampler.root.trace_id_ratio_based.ratio']

        assert_nil ratio, 'Out of range ratio should be transformed to nil'

        transform = SamplerConfigValidator.validate_sampler_strategy_with_ratio(
          :'distributed_tracing.sampler.root',
          :'distributed_tracing.sampler.root.trace_id_ratio_based.ratio'
        )
        result = transform.call('trace_id_ratio_based')

        assert_equal 'adaptive', result
      end
    end

    def test_remote_parent_sampled_strategy_falls_back_to_default_when_ratio_is_invalid
      NewRelic::Agent.logger.stubs(:warn)

      with_config(
        :'distributed_tracing.sampler.remote_parent_sampled.trace_id_ratio_based.ratio' => -0.5
      ) do
        ratio = NewRelic::Agent.config[:'distributed_tracing.sampler.remote_parent_sampled.trace_id_ratio_based.ratio']

        assert_nil ratio, 'Invalid ratio should be transformed to nil'

        transform = SamplerConfigValidator.validate_sampler_strategy_with_ratio(
          :'distributed_tracing.sampler.remote_parent_sampled',
          :'distributed_tracing.sampler.remote_parent_sampled.trace_id_ratio_based.ratio'
        )
        result = transform.call('trace_id_ratio_based')

        assert_equal 'adaptive', result
      end
    end

    def test_remote_parent_not_sampled_strategy_falls_back_to_default_when_ratio_is_invalid
      NewRelic::Agent.logger.stubs(:warn)

      with_config(:'distributed_tracing.sampler.remote_parent_not_sampled.trace_id_ratio_based.ratio' => nil) do
        transform = SamplerConfigValidator.validate_sampler_strategy_with_ratio(
          :'distributed_tracing.sampler.remote_parent_not_sampled',
          :'distributed_tracing.sampler.remote_parent_not_sampled.trace_id_ratio_based.ratio'
        )
        result = transform.call('trace_id_ratio_based')

        assert_equal 'adaptive', result
      end
    end

    def test_other_strategy_values_pass_through_unchanged
      transform = SamplerConfigValidator.validate_sampler_strategy_with_ratio(
        :'distributed_tracing.sampler.root',
        :'distributed_tracing.sampler.root.trace_id_ratio_based.ratio'
      )

      assert_equal 'adaptive', transform.call('adaptive')
      assert_equal 'always_on', transform.call('always_on')
      assert_equal 'always_off', transform.call('always_off')
    end

    def test_warning_logged_when_ratio_is_invalid
      NewRelic::Agent.logger.expects(:warn).with(regexp_matches(/Invalid or missing ratio/)).once

      with_config(:'distributed_tracing.sampler.root.trace_id_ratio_based.ratio' => nil) do
        transform = SamplerConfigValidator.validate_sampler_strategy_with_ratio(
          :'distributed_tracing.sampler.root',
          :'distributed_tracing.sampler.root.trace_id_ratio_based.ratio'
        )
        result = transform.call('trace_id_ratio_based')

        assert_equal 'adaptive', result
      end
    end

    def test_warning_logged_only_once_per_strategy
      SamplerConfigValidator.reset_warnings!

      NewRelic::Agent.logger.expects(:warn).with(regexp_matches(/Invalid or missing ratio/)).once

      with_config(:'distributed_tracing.sampler.root.trace_id_ratio_based.ratio' => nil) do
        transform = SamplerConfigValidator.validate_sampler_strategy_with_ratio(
          :'distributed_tracing.sampler.root',
          :'distributed_tracing.sampler.root.trace_id_ratio_based.ratio'
        )

        # Simulate multiple config sources
        3.times do
          result = transform.call('trace_id_ratio_based')

          assert_equal 'adaptive', result
        end
      end
    end

    def test_different_strategies_log_separate_warnings
      SamplerConfigValidator.reset_warnings!

      # Expect two separate warnings, one for each strategy
      NewRelic::Agent.logger.expects(:warn).with(regexp_matches(/Invalid or missing ratio.*root/)).once
      NewRelic::Agent.logger.expects(:warn).with(regexp_matches(/Invalid or missing ratio.*remote_parent_sampled/)).once

      with_config(
        :'distributed_tracing.sampler.root.trace_id_ratio_based.ratio' => nil,
        :'distributed_tracing.sampler.remote_parent_sampled.trace_id_ratio_based.ratio' => nil
      ) do
        root_transform = SamplerConfigValidator.validate_sampler_strategy_with_ratio(
          :'distributed_tracing.sampler.root',
          :'distributed_tracing.sampler.root.trace_id_ratio_based.ratio'
        )
        root_result = root_transform.call('trace_id_ratio_based')

        assert_equal 'adaptive', root_result

        remote_transform = SamplerConfigValidator.validate_sampler_strategy_with_ratio(
          :'distributed_tracing.sampler.remote_parent_sampled',
          :'distributed_tracing.sampler.remote_parent_sampled.trace_id_ratio_based.ratio'
        )
        remote_result = remote_transform.call('trace_id_ratio_based')

        assert_equal 'adaptive', remote_result
      end
    end

    def test_reset_warnings_clears_state
      with_config(:'distributed_tracing.sampler.root.trace_id_ratio_based.ratio' => nil) do
        transform = SamplerConfigValidator.validate_sampler_strategy_with_ratio(
          :'distributed_tracing.sampler.root',
          :'distributed_tracing.sampler.root.trace_id_ratio_based.ratio'
        )

        NewRelic::Agent.logger.expects(:warn).once
        transform.call('trace_id_ratio_based')

        SamplerConfigValidator.reset_warnings!

        NewRelic::Agent.logger.expects(:warn).once
        transform.call('trace_id_ratio_based')
      end
    end

    def test_config_system_applies_ratio_validation_transform
      with_config(:'distributed_tracing.sampler.root.trace_id_ratio_based.ratio' => 1.5) do
        ratio = NewRelic::Agent.config[:'distributed_tracing.sampler.root.trace_id_ratio_based.ratio']

        assert_nil ratio, 'Expected transform to convert an invalid ratio to nil'
      end
    end

    def test_config_system_preserves_valid_ratios
      with_config(:'distributed_tracing.sampler.root.trace_id_ratio_based.ratio' => 0.7) do
        ratio = NewRelic::Agent.config[:'distributed_tracing.sampler.root.trace_id_ratio_based.ratio']

        assert_in_delta(0.7, ratio)
      end
    end

    def test_config_system_applies_strategy_fallback_when_accessed
      NewRelic::Agent.logger.stubs(:warn)

      with_config(
        :'distributed_tracing.sampler.root' => 'trace_id_ratio_based',
        :'distributed_tracing.sampler.root.trace_id_ratio_based.ratio' => nil
      ) do
        strategy = NewRelic::Agent.config[:'distributed_tracing.sampler.root']

        assert_equal 'adaptive', strategy, "Expected sampler strategy to be 'adaptive' when ratio is invalid"
      end
    end
  end
end
