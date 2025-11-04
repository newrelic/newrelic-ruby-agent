# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Configuration
      # Handles validation and transformation for distributed tracing sampler configurations.
      # This module validates trace_id_ratio_based sampling ratios and ensures parent
      # strategy configs fall back to 'default' when ratios are invalid.
      module SamplerConfigValidator
        # Tracks which sampler strategies have already logged warnings about invalid ratios
        # to ensure we only log once per strategy
        @sampler_strategy_warnings = {}

        class << self
          # Validates and transforms trace_id_ratio_based sampling ratios.
          #
          # @param ratio [Object] the value to validate
          # @return [Float, nil] the ratio if valid, nil otherwise
          #
          # @api private
          def validate_sampling_ratio(ratio)
            return nil if ratio.nil?

            unless ratio.is_a?(Float) && (0.0..1.0).cover?(ratio)
              return nil
            end

            ratio
          end

          # Creates a transform proc that validates a sampler strategy with its associated ratio.
          # When the strategy is 'trace_id_ratio_based', it checks if the ratio is valid.
          # If the ratio is invalid or nil, it falls back to 'default' and logs a warning once.
          #
          # @param strategy_key [Symbol] the config key for the strategy
          #   (e.g., :'distributed_tracing.sampler.root')
          # @param ratio_key [Symbol] the config key for the ratio
          #   (e.g., :'distributed_tracing.sampler.root.trace_id_ratio_based.ratio')
          # @return [Proc] a transform proc for the configuration system
          #
          # @api private
          def validate_sampler_strategy_with_ratio(strategy_key, ratio_key)
            proc do |strategy|
              # If not trace_id_ratio_based, just return the strategy as-is
              next strategy unless strategy == 'trace_id_ratio_based'

              # Get the ratio value
              ratio = NewRelic::Agent.config[ratio_key]

              # If ratio is valid, return the strategy as-is
              if ratio.is_a?(Float) && (0.0..1.0).cover?(ratio)
                next strategy
              end

              # Ratio is invalid or nil, fall back to 'default' and log warning once
              unless @sampler_strategy_warnings[strategy_key]
                NewRelic::Agent.logger.warn(
                  "Invalid or missing ratio for #{ratio_key} (value: #{ratio.inspect}). " \
                  "Falling back to 'default' for #{strategy_key}."
                )
                @sampler_strategy_warnings[strategy_key] = true
              end

              'default'
            end
          end

          # Resets the warning tracking state. Primarily used for testing.
          #
          # @api private
          def reset_warnings!
            @sampler_strategy_warnings = {}
          end
        end
      end
    end
  end
end
